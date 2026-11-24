import Foundation
import Testing

@testable import DiskSpaceHelper

struct CleanupTests {
    @Test func warningThresholdAndCriticalPercentageTriggerAtEquality() {
        let warning = AlertThreshold(id: UUID(), bytes: 5_000_000_000, label: "5 GB")
        let volume = makeVolume(freeBytes: 5_000_000_000)

        #expect(CleanupPolicy.shouldScan(volume, thresholds: [warning]))
        #expect(!CleanupPolicy.shouldScan(makeVolume(freeBytes: 1_000_000_001), thresholds: []))
        #expect(CleanupPolicy.shouldScan(makeVolume(freeBytes: 1_000_000_000), thresholds: []))
    }

    @Test func targetRaisesFreeSpaceAboveTheWarningWhenItExceedsFivePercent() {
        let volume = makeVolume(freeBytes: 1_000_000_000)
        let warning = AlertThreshold(id: UUID(), bytes: 8_000_000_000, label: "8 GB")

        #expect(CleanupPolicy.targetBytes(for: volume, thresholds: []) == 5_000_000_000)
        #expect(CleanupPolicy.targetBytes(for: volume, thresholds: [warning]) == 8_000_000_001)
    }

    @Test func settingsKeepIndependentModelAndExecutableOverrides() throws {
        let suite = "CleanupTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsManager(defaults: defaults)
        #expect(!settings.cleanupEnabled)
        #expect(settings.cleanupModel(for: .claude) == "claude-opus-5-5")
        #expect(settings.cleanupModel(for: .codex) == "gpt-6.2-sol")

        settings.cleanupEnabled = true
        settings.cleanupAgent = .claude
        settings.setCleanupModel("sonnet", for: .claude)
        settings.setCleanupExecutable("/custom/bin/claude", for: .claude)
        let reloaded = SettingsManager(defaults: defaults)

        #expect(reloaded.cleanupEnabled)
        #expect(reloaded.cleanupConfiguration == .init(agent: .claude, model: "sonnet",
                                                       executablePath: "/custom/bin/claude"))
        #expect(reloaded.cleanupModel(for: .codex) == "gpt-6.2-sol")
        #expect(reloaded.cleanupExecutable(for: .codex).isEmpty)
    }

    @Test func structuredRankingResolvesPathsAndSizesFromLocalInventory() throws {
        try withTemporaryDirectory { directory in
            let first = try makeCandidate(in: directory, name: "old installer.dmg")
            let second = try makeCandidate(in: directory, name: "old installer.pkg")
            let ranking = Data(#"{"proposals":[{"title":"Old installer","context":"Can be downloaded again.","candidateIDs":[1]},{"title":"Disk image","context":"Keep if still needed.","candidateIDs":[0]}]}"#.utf8)
            let plan = try CleanupPlan.decode(ranking, inventory: [first, second])

            #expect(plan.proposals[0].candidates.map(\.path) == [second.path])
            #expect(plan.proposals[0].bytes == second.bytes)
        }
    }

    @Test func selectionsFromAnOlderPlanCannotApproveANewPlan() throws {
        try withTemporaryDirectory { directory in
            let first = try makeCandidate(in: directory, name: "first.dmg")
            let second = try makeCandidate(in: directory, name: "second.dmg")
            let ranking = Data(#"{"proposals":[{"title":"Installer","context":"Can be downloaded again.","candidateIDs":[0]}]}"#.utf8)
            let previous = try CleanupPlan.decode(ranking, inventory: [first])
            let refreshed = try CleanupPlan.decode(ranking, inventory: [second])
            let selection = Set(previous.proposals.map(\.id))

            #expect(refreshed.approvedCandidates(for: selection) == nil)
            #expect(previous.approvedCandidates(for: selection)?.map(\.path) == [first.path])
        }
    }

    @Test func aBoundedDirectoryScanKeepsItsPartialSize() throws {
        try withTemporaryDirectory { directory in
            let child = directory.appending(path: "entry")
            let data = Data(repeating: 1, count: 64 * 1_024)
            try data.write(to: child)
            try data.write(to: directory.appending(path: "second-entry"))
            let info = try #require(CleanupFileSystem.status(at: child.path))
            let estimate = CleanupInventory.directorySize(directory, device: info.st_dev, shouldContinue: { true })
            #expect(estimate.bytes == 2 * info.st_blocks * 512)
            #expect(estimate.complete)

            var visited = false
            let partial = CleanupInventory.directorySize(directory, device: info.st_dev) {
                defer { visited = true }
                return !visited
            }
            #expect(partial.bytes == info.st_blocks * 512)
            #expect(!partial.complete)
        }
    }

    @Test func structuredRankingRejectsInventedAndRepeatedCandidateIDs() throws {
        try withTemporaryDirectory { directory in
            let first = try makeCandidate(in: directory, name: "first.dmg")
            let second = try makeCandidate(in: directory, name: "second.dmg")
            for invalidID in [0, 2] {
                let ranking = Data(#"{"proposals":[{"title":"First","context":"Description","candidateIDs":[0]},{"title":"Second","context":"Description","candidateIDs":[\#(invalidID)]}]}"#.utf8)
                #expect(throws: CleanupScanError.invalidResponse) {
                    try CleanupPlan.decode(ranking, inventory: [first, second])
                }
            }
        }
    }

    @Test func removalKeepsTheReplacementWhenAReviewedPathChanges() throws {
        try withTemporaryDirectory { directory in
            let candidate = try makeCandidate(in: directory, name: "old.dmg")
            let path = URL(fileURLWithPath: candidate.path)
            try FileManager.default.moveItem(at: path, to: directory.appending(path: "moved.dmg"))
            try Data("replacement".utf8).write(to: path)

            #expect(throws: CleanupFileSystem.RemovalError.changed) {
                try CleanupFileSystem.remove(candidate)
            }
            #expect(try Data(contentsOf: path) == Data("replacement".utf8))
        }
    }

    @Test func removalDoesNotFollowLinksInsideAnApprovedFolder() throws {
        try withTemporaryDirectory { directory in
            let kept = try makeCandidate(in: directory, name: "keep.dmg")
            let folder = directory.appending(path: "remove")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            _ = try makeCandidate(in: folder, name: "remove.dmg")
            try FileManager.default.createSymbolicLink(at: folder.appending(path: "link"),
                                                       withDestinationURL: URL(fileURLWithPath: kept.path))
            let info = try #require(CleanupFileSystem.status(at: folder.path))
            let candidate = CleanupCandidate(path: folder.path, bytes: 100, kind: .cache, identity: .init(info))

            try CleanupFileSystem.remove(candidate)

            #expect(!FileManager.default.fileExists(atPath: folder.path))
            #expect(FileManager.default.fileExists(atPath: kept.path))
        }
    }

    @Test func claudeCLIReadsStructuredOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = directory.appending(path: "claude")
        let script = """
        #!/bin/sh
        case "$*" in
            --help)
                echo '--safe-mode --strict-mcp-config --json-schema --no-session-persistence'
                ;;
            '--safe-mode auth status --json')
                echo '{"loggedIn":true}'
                ;;
            *)
                echo '{"is_error":false,"structured_output":{"proposals":[{"title":"Installer","context":"Can be downloaded again.","candidateIDs":[0]}]}}'
                ;;
        esac
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let item = try makeCandidate(in: directory, name: "test.dmg")

        let plan = try await CleanupAgentRunner().rank(
            [item], bytesNeeded: 500,
            configuration: .init(agent: .claude, model: CleanupAgent.claude.defaultModel, executablePath: cli.path)
        )

        #expect(plan.proposals.first?.candidates.first?.path == item.path)
    }

    @Test func cancellingTheCLIRunnerAlsoStopsItsChildProcess() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cli = directory.appending(path: "wrapper")
        let running = directory.appending(path: "running")
        let survived = directory.appending(path: "survived")
        let script = """
        #!/bin/sh
        case "$*" in
            --help)
                echo '--safe-mode --strict-mcp-config --json-schema --no-session-persistence'
                ;;
            '--safe-mode auth status --json')
                echo '{"loggedIn":true}'
                ;;
            *)
                (/bin/sleep 1 && /usr/bin/touch '\(survived.path)') &
                /usr/bin/touch '\(running.path)'
                wait
                ;;
        esac
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let candidate = try makeCandidate(in: directory, name: "installer.dmg")
        let configuration = CleanupAgentConfiguration(agent: .claude, model: "fixture", executablePath: cli.path)
        let request = Task {
            try await CleanupAgentRunner().rank([candidate], bytesNeeded: 500, configuration: configuration)
        }
        defer { request.cancel() }

        let deadline = ContinuousClock.now + .seconds(3)
        while !FileManager.default.fileExists(atPath: running.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: running.path))
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
        try await Task.sleep(for: .seconds(1))
        #expect(!FileManager.default.fileExists(atPath: survived.path))
    }

    @Test func agentFailuresRecognizeAuthenticationRateLimitsAndUnavailableModels() {
        #expect(CleanupAgentRunner.classify("Not logged in") == .loggedOut)
        #expect(CleanupAgentRunner.classify(#"{"code":"usage_limit_reached"}"#) == .rateLimited)
        #expect(CleanupAgentRunner.classify("API Error: 429 Too Many Requests") == .rateLimited)
        #expect(CleanupAgentRunner.classify("The model is not supported") == .modelUnavailable)
        #expect(CleanupAgentRunner.classify("Thread 586429237 failed unexpectedly") == .scanFailed)
    }

    @MainActor @Test func manualScanCoversAHealthyVolumeAndOnlyThenOffersReview() {
        let service = CleanupService(notifications: NotificationService(), cacheDirectory: nil)
        let volume = makeVolume(freeBytes: 90_000_000_000)
        let configuration = CleanupAgentConfiguration(agent: .claude, model: "m", executablePath: "/nonexistent")
        service.update(volumes: [volume], thresholds: [], configuration: configuration, quickRecovery: nil, sound: false)
        #expect(service.reviewVolumes.isEmpty)

        service.scanNow(volume.id)
        #expect(service.reviewVolumes.map(\.id) == [volume.id])

        service.update(volumes: [volume], thresholds: [], configuration: nil, quickRecovery: nil, sound: false)
        #expect(service.reviewVolumes.isEmpty)
    }

    private func withTemporaryDirectory(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try #require(CleanupFileSystem.canonicalPath(directory.path))
        try test(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func makeCandidate(in directory: URL, name: String) throws -> CleanupCandidate {
        let path = directory.appending(path: name)
        try Data(name.utf8).write(to: path)
        let info = try #require(CleanupFileSystem.status(at: path.path))
        return CleanupCandidate(path: path.path, bytes: Int64(name.utf8.count), kind: .installer, identity: .init(info))
    }

    private func makeVolume(freeBytes: Int64) -> VolumeInfo {
        VolumeInfo(id: URL(filePath: "/Volumes/Test"), name: "Test", totalBytes: 100_000_000_000,
                   freeBytes: freeBytes)
    }
}
