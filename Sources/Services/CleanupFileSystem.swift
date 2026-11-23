import Darwin
import Foundation

struct CleanupFileIdentity: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let changeTime: Int
    let changeNanoseconds: Int

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        changeTime = info.st_ctimespec.tv_sec
        changeNanoseconds = info.st_ctimespec.tv_nsec
    }
}

enum CleanupFileSystem {
    enum RemovalError: Error {
        case changed
        case inaccessible
    }

    static func status(at path: String) -> stat? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info
    }

    static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(validatingCString: resolved)
    }

    static func volumeRoot(for url: URL) -> URL {
        let data = URL(filePath: "/System/Volumes/Data", directoryHint: .isDirectory)
        return url.path == "/" && status(at: data.path) != nil ? data : url.standardizedFileURL
    }

    static func remove(_ candidate: CleanupCandidate) throws {
        try withParent(of: candidate) { parent, name in
            try remove(name, in: parent, device: candidate.identity.device, expected: candidate.identity)
        }
    }

    static func isCacheFile(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == getuid() && info.st_nlink == 1
    }

    static func removeCacheFile(_ candidate: CacheRecoveryCandidate) throws {
        try withParent(of: candidate.file) { parent, name in
            var info = stat()
            guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0, candidate.matches(info) else {
                throw RemovalError.changed
            }

            let file = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK | O_CLOEXEC)
            guard file >= 0 else { throw RemovalError.inaccessible }
            defer { close(file) }

            guard fstat(file, &info) == 0, candidate.matches(info),
                  fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0, candidate.matches(info) else {
                throw RemovalError.changed
            }
            guard unlinkat(parent, name, 0) == 0 else { throw RemovalError.inaccessible }
        }
    }

    private static func withParent(of candidate: CleanupCandidate, _ operation: (Int32, String) throws -> Void) throws {
        let path = URL(fileURLWithPath: candidate.path)
        let parent = open(path.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parent >= 0 else { throw RemovalError.inaccessible }
        defer { close(parent) }
        var info = stat()
        guard fstat(parent, &info) == 0, info.st_dev == candidate.identity.device else { throw RemovalError.changed }
        try operation(parent, path.lastPathComponent)
    }

    private static func remove(
        _ name: String, in parent: Int32, device: dev_t, expected: CleanupFileIdentity? = nil
    ) throws {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw RemovalError.inaccessible }
        guard info.st_dev == device, expected.map({ $0 == CleanupFileIdentity(info) }) ?? true else {
            throw RemovalError.changed
        }

        let directory = info.st_mode & S_IFMT == S_IFDIR
        if directory {
            try emptyDirectory(name, in: parent, matching: info)
        }

        var current = stat()
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_ino == info.st_ino, current.st_dev == device else { throw RemovalError.changed }
        guard unlinkat(parent, name, directory ? AT_REMOVEDIR : 0) == 0 else { throw RemovalError.inaccessible }
    }

    private static func emptyDirectory(_ name: String, in parent: Int32, matching info: stat) throws {
        let child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw RemovalError.inaccessible }
        guard let directory = fdopendir(child) else {
            close(child)
            throw RemovalError.inaccessible
        }
        defer { closedir(directory) }

        var opened = stat()
        guard fstat(child, &opened) == 0, CleanupFileIdentity(opened) == CleanupFileIdentity(info) else {
            throw RemovalError.changed
        }

        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw RemovalError.inaccessible }
                return
            }
            guard let name = withUnsafePointer(to: &entry.pointee.d_name, { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(validatingCString: $0)
                }
            }) else { throw RemovalError.inaccessible }
            if name != "." && name != ".." {
                try remove(name, in: child, device: info.st_dev)
            }
        }
    }
}
