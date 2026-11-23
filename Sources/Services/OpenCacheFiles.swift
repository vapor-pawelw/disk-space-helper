import Darwin
import Foundation

enum OpenCacheFiles {
    static func inodes(on device: dev_t) -> Set<ino_t>? {
        guard let data = snapshot() else { return nil }

        var result: Set<ino_t> = []
        var fileDevice: dev_t?
        var fileInode: ino_t?
        var foundFileIdentity = false
        for rawField in data.split(separator: 0) {
            let field = rawField.drop(while: { $0 == 10 })
            switch field.first {
            case 112, 102: // p: process, f: file descriptor
                fileDevice = nil
                fileInode = nil
            case 68: // D: hexadecimal device ID
                let value = String(decoding: field.dropFirst(), as: UTF8.self)
                fileDevice = UInt32(value.dropFirst(2), radix: 16).map { dev_t(bitPattern: $0) }
            case 105: // i: inode
                fileInode = ino_t(String(decoding: field.dropFirst(), as: UTF8.self))
            default:
                continue
            }

            if let fileDevice, let fileInode {
                foundFileIdentity = true
                if fileDevice == device { result.insert(fileInode) }
            }
        }
        return foundFileIdentity ? result : nil
    }

    private static func snapshot() -> Data? {
        guard !Task.isCancelled else { return nil }

        let pipe = Pipe()
        let input = pipe.fileHandleForReading
        let fd = input.fileDescriptor
        guard fcntl(fd, F_SETFL, O_NONBLOCK) >= 0 else { return nil }

        let command = Process()
        command.executableURL = URL(filePath: "/usr/sbin/lsof")
        command.arguments = ["-n", "-P", "-u", String(getuid()), "-FfDi0"]
        command.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = pipe
        command.standardError = FileHandle.nullDevice
        do { try command.run() } catch { return nil }
        try? pipe.fileHandleForWriting.close()
        defer {
            if command.isRunning { kill(command.processIdentifier, SIGKILL) }
        }

        let deadline = ContinuousClock.now + .seconds(3)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        var output = Data()
        while !Task.isCancelled, ContinuousClock.now < deadline {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                guard output.count + count <= 8 * 1_024 * 1_024 else { return nil }
                output.append(contentsOf: buffer.prefix(count))
            } else if count == 0, !command.isRunning {
                return command.terminationStatus == 0 ? output : nil
            } else if count < 0, errno != EAGAIN, errno != EINTR {
                return nil
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        return nil
    }
}
