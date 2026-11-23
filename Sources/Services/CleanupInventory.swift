import Darwin
import Foundation

enum CleanupInventory {
    private static let minimumBytes: Int64 = 32 * 1_024 * 1_024
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "iso"]
    private static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "7z", "rar", "xz", "bz2", "xip"]

    static func scan(_ volume: VolumeInfo) throws -> [CleanupCandidate] {
        let root = CleanupFileSystem.volumeRoot(for: volume.id)
        guard let info = CleanupFileSystem.status(at: root.path) else { throw CleanupScanError.scanFailed }

        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let homeIsOnVolume = CleanupFileSystem.status(at: home.path)?.st_dev == info.st_dev
        let scanner = Scanner(device: info.st_dev)
        if homeIsOnVolume {
            scanner.collectChildren(of: home.appending(path: ".Trash"), kind: .trash)
            scanner.walk(home.appending(path: "Downloads"), oldDownloads: true)
            scanner.collectChildren(of: home.appending(path: "Library/Developer/Xcode/Archives"), kind: .xcodeArchive)
            scanner.collectChildren(of: home.appending(path: "Library/Developer/Xcode/DerivedData"), kind: .buildOutput)
            scanner.collectChildren(of: home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport"), kind: .buildOutput)
            scanner.walk(home, excluding: ["Downloads", "Library", "Applications"])
            scanner.collectChildren(of: home.appending(path: "Library/Caches"), kind: .cache)
            scanner.collectChildren(of: home.appending(path: ".gradle/caches"), kind: .dependencyCache)
        }

        let shared = root.appending(path: "Users/Shared")
        scanner.walk(shared)
        scanner.walk(root, excluding: [
            "Applications", "Library", "System", "Users", "Volumes",
            "bin", "cores", "dev", "etc", "private", "sbin", "tmp", "usr", "var",
        ])
        try Task.checkCancellation()
        return scanner.candidates
    }

    struct DirectorySize {
        var bytes: Int64 = 0
        var complete = true
    }

    static func directorySize(_ root: URL, device: dev_t, shouldContinue: () -> Bool) -> DirectorySize {
        var size = DirectorySize()
        guard let entries = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [],
            errorHandler: { _, _ in
                size.complete = false
                return true
            }
        ) else { return DirectorySize(complete: false) }

        for case let url as URL in entries {
            guard shouldContinue() else {
                size.complete = false
                break
            }
            guard let info = CleanupFileSystem.status(at: url.path), info.st_dev == device else {
                size.complete = false
                entries.skipDescendants()
                continue
            }
            size.bytes += allocatedBytes(info)
        }
        return size
    }

    private static func allocatedBytes(_ info: stat) -> Int64 {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { return 0 }
        return info.st_blocks * 512
    }

    private final class Scanner {
        let device: dev_t
        let deadline = ContinuousClock.now + .seconds(45)
        let cutoff = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        var seen: Set<ino_t> = []
        var byKind: [CleanupCandidate.Kind: [CleanupCandidate]] = [:]

        init(device: dev_t) {
            self.device = device
        }

        var candidates: [CleanupCandidate] {
            byKind.values.flatMap { $0 }.sorted { lhs, rhs in
                if lhs.kind.priority != rhs.kind.priority { return lhs.kind.priority < rhs.kind.priority }
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.path < rhs.path
            }
        }

        private var canContinue: Bool { !Task.isCancelled && ContinuousClock.now < deadline }

        func walk(_ root: URL, oldDownloads: Bool = false, excluding: Set<String> = []) {
            guard canContinue, let info = status(root), info.st_mode & S_IFMT == S_IFDIR,
                  let entries = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [], options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                  ) else { return }

            let walkDeadline = ContinuousClock.now + .seconds(10)
            for case let url as URL in entries {
                guard canContinue, ContinuousClock.now < walkDeadline else { break }
                guard entries.level != 1 || !excluding.contains(url.lastPathComponent),
                      let info = status(url) else {
                    entries.skipDescendants()
                    continue
                }
                if info.st_mode & S_IFMT == S_IFDIR {
                    if url.lastPathComponent == "node_modules", info.st_uid == getuid() {
                        let size = directorySize(url)
                        add(url, info: info, kind: .dependencyCache, bytes: size.bytes, isPartial: !size.complete)
                        entries.skipDescendants()
                    }
                    continue
                }
                guard info.st_uid == getuid(),
                      let kind = fileKind(url, info: info, oldDownloads: oldDownloads) else { continue }
                add(url, info: info, kind: kind, bytes: CleanupInventory.allocatedBytes(info))
            }
        }

        func collectChildren(of root: URL, kind: CleanupCandidate.Kind) {
            guard canContinue, let rootInfo = status(root), rootInfo.st_mode & S_IFMT == S_IFDIR,
                  let children = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [], options: [.skipsSubdirectoryDescendants]
                  ) else { return }

            let rootDeadline = ContinuousClock.now + .seconds(6)
            for case let url as URL in children {
                guard canContinue, ContinuousClock.now < rootDeadline else { break }
                guard let info = status(url), info.st_uid == getuid() else { continue }
                let size = info.st_mode & S_IFMT == S_IFDIR ? directorySize(url, before: rootDeadline)
                    : DirectorySize(bytes: CleanupInventory.allocatedBytes(info))
                add(url, info: info, kind: kind, bytes: size.bytes, isPartial: !size.complete)
            }
        }

        private func fileKind(_ url: URL, info: stat, oldDownloads: Bool) -> CleanupCandidate.Kind? {
            let ext = url.pathExtension.lowercased()
            if CleanupInventory.installerExtensions.contains(ext) { return .installer }
            let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
            guard modified < cutoff else { return nil }
            if CleanupInventory.archiveExtensions.contains(ext) { return .archive }
            return oldDownloads ? .oldDownload : nil
        }

        private func directorySize(_ root: URL, before deadline: ContinuousClock.Instant? = nil) -> DirectorySize {
            let limit = min(deadline ?? self.deadline, ContinuousClock.now + .seconds(2))
            return CleanupInventory.directorySize(root, device: device) { canContinue && ContinuousClock.now < limit }
        }

        private func status(_ url: URL) -> stat? {
            guard !url.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  let info = CleanupFileSystem.status(at: url.path),
                  info.st_dev == device,
                  [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT) else { return nil }
            return info
        }

        private func add(_ url: URL, info: stat, kind: CleanupCandidate.Kind, bytes: Int64, isPartial: Bool = false) {
            guard bytes >= CleanupInventory.minimumBytes,
                  let path = CleanupFileSystem.canonicalPath(url.path),
                  let resolved = CleanupFileSystem.status(at: path),
                  CleanupFileIdentity(resolved) == CleanupFileIdentity(info),
                  seen.insert(info.st_ino).inserted else { return }
            var candidates = byKind[kind, default: []]
            candidates.append(.init(path: path, bytes: bytes, kind: kind, identity: .init(info), isPartial: isPartial))
            candidates.sort { $0.bytes == $1.bytes ? $0.path < $1.path : $0.bytes > $1.bytes }
            byKind[kind] = Array(candidates.prefix(12))
        }
    }
}
