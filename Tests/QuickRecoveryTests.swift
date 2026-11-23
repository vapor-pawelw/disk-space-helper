import Darwin
import Foundation
import Testing

@testable import DiskSpaceHelper

struct QuickRecoveryTests {
    @Test func onlyStartsBelowOnePercentOfImmediatelyAvailableSpace() {
        #expect(QuickRecovery.shouldRun(on: volume(freeBytes: 999_999_999)))
        #expect(!QuickRecovery.shouldRun(on: volume(freeBytes: 1_000_000_000)))
        #expect(!QuickRecovery.shouldRun(on: volume(freeBytes: 1_500_000_000)))
    }

    @MainActor @Test func criticalRecoveryTakesPriorityOverSuggestions() {
        let cache = FileManager.default.temporaryDirectory
        let service = CleanupService(notifications: NotificationService(), cacheDirectory: cache)
        let configuration = CleanupAgentConfiguration(agent: .codex, model: "test", executablePath: "")
        let critical = VolumeInfo(id: cache, name: "Fixture", totalBytes: 100_000_000_000, freeBytes: 0)
        let warning = volume(freeBytes: 1_000_000_000)

        service.update(volumes: [warning], thresholds: [], configuration: configuration, quickRecovery: nil, sound: false)
        guard case .scanning = service.statuses[warning.id] else {
            Issue.record("Expected the warning to start a suggestion scan")
            return
        }

        service.update(volumes: [warning, critical], thresholds: [], configuration: configuration,
                       quickRecovery: configuration, sound: false)
        #expect(service.statuses[critical.id] == nil)

        service.update(volumes: [], thresholds: [], configuration: nil, quickRecovery: nil, sound: false)
    }

    @Test func agentSelectionSkipsFilesThatBecomeActiveAndStopsWhenSpaceRecovers() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = URL(filePath: try #require(CleanupFileSystem.canonicalPath(directory.path)))
        let cache = root.appending(path: "SomeApp")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let chosen = try cachedFile("agent-picked.data", in: cache)
        let unchosen = try cachedFile("agent-skipped.data", in: cache)
        let spare = try cachedFile("selected-but-no-longer-needed.data", in: cache)
        let opened = try cachedFile("now-open.data", in: cache)
        let accessed = try cachedFile("now-accessed.data", in: cache)
        let symlink = cache.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: unchosen)

        let inventory = try QuickRecovery.inventory(in: root, on: root)
        #expect(!inventory.contains { $0.file.path == symlink.path })
        let ids = try [opened, accessed, chosen, spare].map { item in
            try #require(inventory.firstIndex { $0.file.path == item.path })
        }
        let cli = directory.appending(path: "test-cli")
        let rawIDs = ids.map(String.init).joined(separator: ",")
        let script = """
        #!/bin/sh
        case "$*" in
            --help)
                echo '--safe-mode --strict-mcp-config --json-schema --no-session-persistence'
                ;;
            '--safe-mode auth status --json')
                echo '{"loggedIn":true}'
                ;;
            *--model*"fixture-model"*"hoursSinceAccess"*)
                echo '{"is_error":false,"structured_output":{"candidateIDs":[\(rawIDs)]}}'
                ;;
            *)
                exit 2
                ;;
        esac
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let configuration = CleanupAgentConfiguration(agent: .claude, model: "fixture-model", executablePath: cli.path)
        let selected = try await CleanupAgentRunner().selectCacheFiles(inventory, bytesNeeded: 2_000_000,
                                                                      configuration: configuration)
        #expect(selected.map(\.file.path) == [opened.path, accessed.path, chosen.path, spare.path])

        let currentReader = try FileHandle(forReadingFrom: opened)
        defer { try? currentReader.close() }
        let now = Int(Date.now.timeIntervalSince1970)
        let changedAt = [timespec(tv_sec: now, tv_nsec: 0), timespec(tv_sec: now, tv_nsec: 0)]
        try #require(utimensat(AT_FDCWD, accessed.path, changedAt, 0) == 0)

        let result = try QuickRecovery.apply(selected, on: root) {
            FileManager.default.fileExists(atPath: chosen.path)
        }

        #expect(result.removedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: chosen.path))
        for retained in [opened, accessed, unchosen, spare, symlink] {
            #expect(FileManager.default.fileExists(atPath: retained.path))
        }
        #expect(throws: CleanupScanError.invalidResponse) {
            try QuickRecovery.selection(from: Data(#"{"candidateIDs":[999]}"#.utf8), inventory: inventory)
        }
    }

    @Test func failedOpenFileCheckIsDifferentFromAnEmptyInventory() throws {
        let root = FileManager.default.temporaryDirectory
        let directory = try #require(CleanupFileSystem.canonicalPath(root.path))
        let canonical = URL(filePath: directory, directoryHint: .isDirectory)

        #expect(throws: CleanupScanError.fileUseUnavailable) {
            try QuickRecovery.inventory(in: canonical, on: canonical) { _ in nil }
        }
    }

    @Test func quickRecoveryWaitsThirtyMinutesBeforeAnotherCriticalAttempt() {
        let now = ContinuousClock.now
        #expect(QuickRecovery.canAttempt(lastAttempt: nil, now: now))
        #expect(!QuickRecovery.canAttempt(lastAttempt: now - .seconds(1_799), now: now))
        #expect(QuickRecovery.canAttempt(lastAttempt: now - .seconds(1_800), now: now))
    }

    @Test func quickRecoveryHasItsOwnOptIn() throws {
        let name = "QuickRecoveryTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = SettingsManager(defaults: defaults)
        #expect(!settings.quickRecoveryEnabled)
        settings.quickRecoveryEnabled = true
        settings.save()

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.quickRecoveryEnabled)
        #expect(!reloaded.cleanupEnabled)
    }

    private func volume(freeBytes: Int64) -> VolumeInfo {
        VolumeInfo(id: URL(filePath: "/Volumes/Test"), name: "Test", totalBytes: 100_000_000_000,
                   freeBytes: 8_000_000_000, cleanupFreeBytes: freeBytes)
    }

    private func cachedFile(_ name: String, in directory: URL, lastAccessDaysAgo: Int = 60) throws -> URL {
        let path = directory.appending(path: name)
        try Data(repeating: 42, count: 2 * 1_024 * 1_024).write(to: path)
        let now = Int(Date.now.timeIntervalSince1970)
        let access = timespec(tv_sec: now - lastAccessDaysAgo * 86_400, tv_nsec: 0)
        let modified = timespec(tv_sec: now - 60 * 86_400, tv_nsec: 0)
        let timestamps = [access, modified]
        try #require(utimensat(AT_FDCWD, path.path, timestamps, 0) == 0)
        return path
    }
}
