import Foundation

@MainActor
@Observable
final class CleanupService {
    enum Status {
        case scanning(attempt: Int)
        case ready(CleanupPlan)
        case noCandidates
        case failed(CleanupScanError, CleanupAgent)
        case deleting
    }

    struct RemovalResult {
        let removedCount: Int
        let failedPaths: [String]
    }

    private enum Work: Equatable {
        case suggestions(URL)
        case recovery(URL)
    }

    private(set) var statuses: [URL: Status] = [:]
    private(set) var activeVolumes: [VolumeInfo] = []
    private(set) var removalResults: [URL: RemovalResult] = [:]
    private var quickRecoveryNotice: (message: String, expires: ContinuousClock.Instant)?
    var quickRecoverySummary: String? { quickRecoveryNotice?.message }
    var refreshVolumes: (() -> Void)?

    private let notifications: NotificationService
    private let agent = CleanupAgentRunner()
    private let cacheDirectory: URL?
    private var configuration: CleanupAgentConfiguration?
    private var recoveryConfiguration: CleanupAgentConfiguration?
    private var thresholds: [AlertThreshold] = []
    private var trackedVolumes: [VolumeInfo] = []
    private var soundEnabled = true
    /// Volumes the user asked to scan regardless of the free-space thresholds.
    private var manualScans: Set<URL> = []
    private var lastRecoveryAttempts: [URL: ContinuousClock.Instant] = [:]
    private var work: (kind: Work, task: Task<Void, Never>)?

    init(notifications: NotificationService, cacheDirectory: URL? = QuickRecovery.cacheDirectory) {
        self.notifications = notifications
        self.cacheDirectory = cacheDirectory
    }

    var needsAttention: Bool {
        statuses.values.contains {
            switch $0 {
            case .ready, .failed, .noCandidates: true
            case .scanning, .deleting: false
            }
        }
    }

    /// Volumes with something to review: an active scan or a recent removal result.
    var reviewVolumes: [VolumeInfo] {
        let active = Set(activeVolumes.map(\.id))
        return activeVolumes + trackedVolumes.filter { removalResults[$0.id] != nil && !active.contains($0.id) }
    }

    func update(
        volumes: [VolumeInfo], thresholds: [AlertThreshold], configuration: CleanupAgentConfiguration?,
        quickRecovery: CleanupAgentConfiguration?, sound: Bool
    ) {
        trackedVolumes = volumes
        self.thresholds = thresholds
        soundEnabled = sound
        if self.configuration != configuration {
            if case .suggestions = work?.kind { work?.task.cancel() }
            for (id, status) in statuses {
                switch status {
                case .failed, .noCandidates: clearStatus(id)
                default: break
                }
            }
            manualScans = []
            self.configuration = configuration
        }
        if recoveryConfiguration != quickRecovery {
            if case .recovery = work?.kind { work?.task.cancel() }
            quickRecoveryNotice = nil
            recoveryConfiguration = quickRecovery
        }

        updateActiveVolumes()
        if case .suggestions(let id) = work?.kind, !activeVolumes.contains(where: { $0.id == id }) {
            work?.task.cancel()
        }
        if case .recovery(let id) = work?.kind,
           !volumes.contains(where: { $0.id == id && QuickRecovery.shouldRun(on: $0) }) {
            work?.task.cancel()
        }
        if let quickRecoveryNotice, quickRecoveryNotice.expires <= .now {
            self.quickRecoveryNotice = nil
        }
        startNextWork()
    }

    func scanNow(_ id: URL) {
        guard configuration != nil, trackedVolumes.contains(where: { $0.id == id }) else { return }
        switch statuses[id] {
        case .scanning, .deleting: return
        default: break
        }
        manualScans.insert(id)
        clearStatus(id)
        updateActiveVolumes()
        startNextWork()
    }

    func retry(_ id: URL) {
        guard activeVolumes.contains(where: { $0.id == id }) else { return }
        switch statuses[id] {
        case .scanning, .deleting: return
        default: break
        }
        clearStatus(id)
        startNextWork()
    }

    func delete(_ approvedIDs: Set<UUID>, from id: URL) async -> Bool {
        guard work?.kind != .recovery(id), case .ready(let current) = statuses[id],
              let candidates = current.approvedCandidates(for: approvedIDs) else { return false }

        statuses[id] = .deleting
        notifications.clearCleanupNotification(for: id)
        let result = await Task.detached(priority: .utility) {
            var failed: [String] = []
            for candidate in candidates {
                do {
                    try CleanupFileSystem.remove(candidate)
                } catch {
                    failed.append(candidate.path)
                }
            }
            return RemovalResult(removedCount: candidates.count - failed.count, failedPaths: failed)
        }.value
        removalResults[id] = result

        if configuration != nil, activeVolumes.contains(where: { $0.id == id }) {
            let remaining = current.proposals.filter { !approvedIDs.contains($0.id) }
            statuses[id] = remaining.isEmpty ? .noCandidates : .ready(.init(proposals: remaining))
        } else {
            clearStatus(id)
        }
        return true
    }

    private func updateActiveVolumes() {
        var roots: Set<String> = []
        activeVolumes = configuration == nil ? [] : trackedVolumes
            .sorted { $0.cleanupFreeBytes < $1.cleanupFreeBytes }
            .filter { volume in
                let belowWarning = CleanupPolicy.shouldScan(volume, thresholds: thresholds)
                let target = CleanupPolicy.targetBytes(for: volume, thresholds: thresholds)
                let belowActiveTarget = statuses[volume.id] != nil && volume.cleanupFreeBytes < target
                return (belowWarning || belowActiveTarget || manualScans.contains(volume.id))
                    && roots.insert(CleanupFileSystem.volumeRoot(for: volume.id).path).inserted
            }

        let activeIDs = Set(activeVolumes.map(\.id))
        for id in statuses.keys where !activeIDs.contains(id) {
            if case .deleting = statuses[id] { continue }
            clearStatus(id)
        }
    }

    private func startNextWork() {
        if let configuration = recoveryConfiguration, let cache = cacheDirectory,
           let next = recoveryVolume(cache: cache) {
            if let work {
                if case .suggestions = work.kind { work.task.cancel() }
                return
            }
            startRecovery(for: next.volume, at: next.root, cache: cache, configuration: configuration)
            return
        }

        guard work == nil, let configuration,
              let volume = activeVolumes.first(where: { statuses[$0.id] == nil }) else { return }
        let target = CleanupPolicy.targetBytes(for: volume, thresholds: thresholds)
        var needed = max(0, target - volume.cleanupFreeBytes)
        // A healthy volume needs nothing, so a manual scan asks for 5% of its capacity.
        if manualScans.contains(volume.id) { needed = max(needed, volume.totalBytes / 20) }
        statuses[volume.id] = .scanning(attempt: 1)
        let task = Task {
            await scanVolume(volume, needed: needed, configuration: configuration)
            if Task.isCancelled, case .scanning = statuses[volume.id] { clearStatus(volume.id) }
            work = nil
            updateActiveVolumes()
            startNextWork()
        }
        work = (.suggestions(volume.id), task)
    }

    private func recoveryVolume(cache: URL) -> (volume: VolumeInfo, root: URL)? {
        let critical = trackedVolumes.filter { QuickRecovery.shouldRun(on: $0) }
        guard !critical.isEmpty, let device = CleanupFileSystem.status(at: cache.path)?.st_dev else { return nil }
        let now = ContinuousClock.now
        for volume in critical {
            if case .deleting = statuses[volume.id] { continue }
            let root = CleanupFileSystem.volumeRoot(for: volume.id)
            guard QuickRecovery.canAttempt(lastAttempt: lastRecoveryAttempts[root], now: now),
                  CleanupFileSystem.status(at: root.path)?.st_dev == device else { continue }
            return (volume, root)
        }
        return nil
    }

    private func startRecovery(
        for volume: VolumeInfo, at root: URL, cache: URL, configuration: CleanupAgentConfiguration
    ) {
        lastRecoveryAttempts[root] = .now
        quickRecoveryNotice = nil
        let task = Task {
            let worker = Task.detached(priority: .utility) {
                try await QuickRecovery.recover(from: cache, on: root, volume: volume, configuration: configuration)
            }
            let outcome = await withTaskCancellationHandler {
                await worker.result
            } onCancel: {
                worker.cancel()
            }
            work = nil
            finishRecovery(outcome, volume: volume, configuration: configuration)
            if let refreshVolumes { refreshVolumes() }
            else { startNextWork() }
        }
        work = (.recovery(volume.id), task)
    }

    private func finishRecovery(
        _ outcome: Result<QuickRecovery.Outcome, Error>, volume: VolumeInfo, configuration: CleanupAgentConfiguration
    ) {
        let message: String
        switch outcome {
        case .success(.removed(let result)):
            message = String(localized: .Cleanup.recoveryRemoved(formatBytes(result.allocatedBytes), volume.name))
        case .success(.noCandidates):
            message = String(localized: .Cleanup.recoveryNoCandidates(volume.name))
        case .success(.candidatesChanged):
            message = String(localized: .Cleanup.recoveryCandidatesChanged(volume.name))
        case .failure(let error) where !(error is CancellationError):
            message = (error as? CleanupScanError ?? .scanFailed).message(for: configuration.agent)
        default:
            return
        }
        if recoveryConfiguration != nil { quickRecoveryNotice = (message, .now + .seconds(30 * 60)) }
        notifications.postQuickRecoveryNotification(volume: volume.name, message: message, sound: soundEnabled)
    }

    private func scanVolume(_ volume: VolumeInfo, needed: Int64, configuration: CleanupAgentConfiguration) async {
        do {
            try Task.checkCancellation()
            let inventoryTask = Task.detached(priority: .utility) { try CleanupInventory.scan(volume) }
            let inventory = try await withTaskCancellationHandler {
                try await inventoryTask.value
            } onCancel: {
                inventoryTask.cancel()
            }
            try Task.checkCancellation()

            guard !inventory.isEmpty else {
                finishScan(.noCandidates, volume: volume)
                return
            }

            for attempt in 1...3 {
                try Task.checkCancellation()
                statuses[volume.id] = .scanning(attempt: attempt)
                do {
                    let plan = try await agent.rank(inventory, bytesNeeded: needed, configuration: configuration)
                    try Task.checkCancellation()
                    finishScan(.ready(plan), volume: volume)
                    return
                } catch {
                    try Task.checkCancellation()
                    let failure = error as? CleanupScanError ?? .scanFailed
                    guard attempt < 3, failure.retryable else {
                        finishScan(.failed(failure, configuration.agent), volume: volume)
                        return
                    }
                    try await Task.sleep(for: failure.retryDelay(after: attempt))
                }
            }
        } catch is CancellationError {
            return
        } catch {
            finishScan(.failed(.scanFailed, configuration.agent), volume: volume)
        }
    }

    private func finishScan(_ status: Status, volume: VolumeInfo) {
        guard !Task.isCancelled else { return }
        statuses[volume.id] = status
        let message: String
        switch status {
        case .ready(let plan):
            let amount = formatBytes(plan.proposals.reduce(0) { $0 + $1.bytes })
            message = plan.proposals.contains(where: \.isPartial)
                ? String(localized: .Cleanup.reviewPartiallyMeasured(volume.name, amount))
                : String(localized: .Cleanup.reviewEstimated(volume.name, amount))
        case .failed(let failure, let provider):
            message = failure.message(for: provider)
        case .noCandidates:
            message = String(localized: .Cleanup.scanFoundNoCandidates(volume.name))
        case .scanning, .deleting: return
        }
        notifications.postCleanupNotification(for: volume.id, message: message, sound: soundEnabled)
    }

    private func clearStatus(_ id: URL) {
        statuses[id] = nil
        notifications.clearCleanupNotification(for: id)
    }
}
