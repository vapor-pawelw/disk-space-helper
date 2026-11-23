import Darwin
import Foundation

struct CacheRecoveryCandidate: Sendable {
    let file: CleanupCandidate
    let lastAccessSeconds: Int
    let lastAccessNanoseconds: Int
    let lastModifiedSeconds: Int

    init(path: String, info: stat) {
        file = .init(path: path, bytes: info.st_blocks * 512, kind: .cache, identity: .init(info))
        lastAccessSeconds = info.st_atimespec.tv_sec
        lastAccessNanoseconds = info.st_atimespec.tv_nsec
        lastModifiedSeconds = info.st_mtimespec.tv_sec
    }

    func matches(_ info: stat) -> Bool {
        CleanupFileSystem.isCacheFile(info) && file.identity == CleanupFileIdentity(info)
            && lastAccessSeconds == info.st_atimespec.tv_sec && lastAccessNanoseconds == info.st_atimespec.tv_nsec
    }
}

enum QuickRecovery {
    struct Result: Sendable {
        var removedFiles = 0
        var allocatedBytes: Int64 = 0
    }

    enum Outcome: Sendable {
        case removed(Result)
        case noCandidates
        case candidatesChanged
        case pressureCleared
    }

    static func canAttempt(lastAttempt: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let lastAttempt else { return true }
        return now - lastAttempt >= .seconds(30 * 60)
    }

    static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    static func shouldRun(on volume: VolumeInfo) -> Bool {
        volume.totalBytes > 0 && volume.cleanupFreeBytes < minimumFreeBytes(total: volume.totalBytes)
    }

    static func recover(
        from cache: URL, on volumeRoot: URL, volume: VolumeInfo, configuration: CleanupAgentConfiguration
    ) async throws -> Outcome {
        try Task.checkCancellation()
        let minimum = minimumFreeBytes(total: volume.totalBytes)
        func bytesNeeded() -> Int64? {
            let freshVolume = URL(filePath: volumeRoot.path)
            guard let free = try? freshVolume.resourceValues(forKeys: [.volumeAvailableCapacityKey])
                .volumeAvailableCapacity else { return nil }
            return max(0, minimum - Int64(free))
        }

        guard let needed = bytesNeeded() else { throw CleanupScanError.scanFailed }
        guard needed > 0 else { return .pressureCleared }
        let candidates = try inventory(in: cache, on: volumeRoot)
        try Task.checkCancellation()
        guard !candidates.isEmpty else { return .noCandidates }

        let agent = CleanupAgentRunner()
        for attempt in 1...3 {
            try Task.checkCancellation()
            guard let needed = bytesNeeded() else { throw CleanupScanError.scanFailed }
            guard needed > 0 else { return .pressureCleared }
            let selected: [CacheRecoveryCandidate]
            do {
                selected = try await agent.selectCacheFiles(candidates, bytesNeeded: needed, configuration: configuration)
            } catch {
                try Task.checkCancellation()
                let failure = error as? CleanupScanError ?? .scanFailed
                guard attempt < 3, failure.retryable else { throw failure }
                try await Task.sleep(for: failure.retryDelay(after: attempt))
                continue
            }
            try Task.checkCancellation()
            guard !selected.isEmpty else { return .noCandidates }
            let result = try apply(selected, on: volumeRoot) { (bytesNeeded() ?? 0) > 0 }
            if result.removedFiles > 0 { return .removed(result) }
            try Task.checkCancellation()
            guard let remaining = bytesNeeded() else { throw CleanupScanError.scanFailed }
            return remaining > 0 ? .candidatesChanged : .pressureCleared
        }
        throw CleanupScanError.scanFailed
    }

    static func inventory(
        in cache: URL, on volumeRoot: URL, openFiles: (dev_t) -> Set<ino_t>? = OpenCacheFiles.inodes
    ) throws -> [CacheRecoveryCandidate] {
        guard CleanupFileSystem.canonicalPath(cache.path) == cache.path,
              let volume = CleanupFileSystem.status(at: volumeRoot.path),
              CleanupFileSystem.status(at: cache.path)?.st_dev == volume.st_dev,
              let entries = FileManager.default.enumerator(at: cache, includingPropertiesForKeys: [],
                                                           options: [.skipsHiddenFiles]) else {
            throw CleanupScanError.scanFailed
        }
        guard let openInodes = openFiles(volume.st_dev) else {
            try Task.checkCancellation()
            throw CleanupScanError.fileUseUnavailable
        }

        let deadline = ContinuousClock.now + .seconds(5)
        var candidates: [CacheRecoveryCandidate] = []
        for case let file as URL in entries {
            guard !Task.isCancelled, ContinuousClock.now < deadline else { break }
            guard let info = CleanupFileSystem.status(at: file.path), info.st_dev == volume.st_dev,
                  info.st_mode & S_IFMT != S_IFLNK else {
                entries.skipDescendants()
                continue
            }
            guard CleanupFileSystem.isCacheFile(info), info.st_blocks > 0,
                  !openInodes.contains(info.st_ino),
                  !file.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { continue }
            candidates.append(.init(path: file.path, info: info))
        }

        let bySize = candidates.sorted {
            $0.file.bytes == $1.file.bytes ? $0.file.path < $1.file.path : $0.file.bytes > $1.file.bytes
        }
        let largest = bySize.prefix(96)
        let oldest = bySize.dropFirst(largest.count).prefix(512).sorted { left, right in
            let leftUse = max(left.lastAccessSeconds, left.lastModifiedSeconds)
            let rightUse = max(right.lastAccessSeconds, right.lastModifiedSeconds)
            return leftUse == rightUse ? left.file.bytes > right.file.bytes : leftUse < rightUse
        }
        return Array(largest) + oldest.prefix(32)
    }

    static func selection(from data: Data, inventory: [CacheRecoveryCandidate]) throws -> [CacheRecoveryCandidate] {
        guard let reply = try? JSONDecoder().decode(Selection.self, from: data) else {
            throw CleanupScanError.invalidResponse
        }
        var used: Set<Int> = []
        return try reply.candidateIDs.map { id in
            guard inventory.indices.contains(id), used.insert(id).inserted else {
                throw CleanupScanError.invalidResponse
            }
            return inventory[id]
        }
    }

    static func apply(
        _ selected: [CacheRecoveryCandidate], on volumeRoot: URL, stillCritical: () -> Bool
    ) throws -> Result {
        guard !selected.isEmpty, !Task.isCancelled, stillCritical() else { return Result() }
        guard let volume = CleanupFileSystem.status(at: volumeRoot.path) else { throw CleanupScanError.scanFailed }
        guard let openInodes = OpenCacheFiles.inodes(on: volume.st_dev) else {
            try Task.checkCancellation()
            throw CleanupScanError.fileUseUnavailable
        }

        var result = Result()
        for candidate in selected {
            guard !Task.isCancelled, stillCritical() else { break }
            guard candidate.file.identity.device == volume.st_dev,
                  !openInodes.contains(candidate.file.identity.inode) else { continue }
            do {
                try CleanupFileSystem.removeCacheFile(candidate)
                result.removedFiles += 1
                result.allocatedBytes += candidate.file.bytes
            } catch {
                continue
            }
        }
        return result
    }

    private static func minimumFreeBytes(total: Int64) -> Int64 {
        total / 100 + (total % 100 == 0 ? 0 : 1)
    }

    private struct Selection: Decodable {
        let candidateIDs: [Int]
    }
}
