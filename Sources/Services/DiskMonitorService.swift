import Foundation

private let volumeResourceKeys: Set<URLResourceKey> = [
    .volumeIsInternalKey,
    .volumeIsRemovableKey,
    .volumeIsLocalKey,
    .volumeIsReadOnlyKey,
    .volumeTotalCapacityKey,
    .volumeAvailableCapacityKey,
    .volumeAvailableCapacityForImportantUsageKey,
    .volumeNameKey,
]

@MainActor
@Observable
final class DiskMonitorService {
    private(set) var volumes: [VolumeInfo] = []
    private var timer: Timer?
    let settings = SettingsManager()
    let notifications: NotificationService
    let cleanup: CleanupService

    init() {
        let notifications = NotificationService()
        self.notifications = notifications
        self.cleanup = CleanupService(notifications: notifications)
        self.cleanup.refreshVolumes = { [weak self] in self?.pollVolumes() }
    }

    var trackedVolumes: [VolumeInfo] {
        let tracked = settings.trackedVolumeURLs
        if tracked.isEmpty { return volumes }
        return volumes.filter { tracked.contains($0.id) }
    }

    var lowestFreePercentage: Double? {
        trackedVolumes.map(\.freePercentage).min()
    }

    var menuBarTitle: String {
        guard let pct = lowestFreePercentage else { return "" }
        let display = settings.showUsedPercentage ? Int(100 - pct) : Int(pct)
        return "\(display)%"
    }

    private var monitoringInterval: TimeInterval { settings.quickRecoveryEnabled ? 15 : 60 }

    func startMonitoring() {
        guard timer == nil else { return }
        let interval = monitoringInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollVolumes() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        pollVolumes()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func setQuickRecoveryEnabled(_ enabled: Bool) {
        guard settings.quickRecoveryEnabled != enabled else { return }
        settings.quickRecoveryEnabled = enabled
        settings.save()
        applyCleanupSettings()
    }

    func applyCleanupSettings() {
        if timer?.timeInterval == monitoringInterval {
            evaluateCleanup()
        } else {
            stopMonitoring()
            startMonitoring()
        }
    }

    func pollVolumes() {
        guard let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeResourceKeys),
            options: [.skipHiddenVolumes]
        ) else {
            evaluateCleanup()
            return
        }

        volumes = mountedURLs.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: volumeResourceKeys) else {
                return nil
            }

            guard values.volumeIsInternal == true,
                  values.volumeIsRemovable == false,
                  values.volumeIsLocal == true,
                  values.volumeIsReadOnly != true,
                  let total = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacityForImportantUsage,
                  let name = values.volumeName
            else { return nil }

            // Skip system volumes that aren't user-relevant
            let path = url.path
            if path.hasPrefix("/System/Volumes/") && path != "/System/Volumes/Data" {
                return nil
            }

            return VolumeInfo(
                id: url,
                name: name,
                totalBytes: Int64(total),
                freeBytes: free,
                cleanupFreeBytes: values.volumeAvailableCapacity.map(Int64.init)
            )
        }

        notifications.evaluateThresholds(
            volumes: trackedVolumes,
            thresholds: settings.alertThresholds,
            soundEnabled: settings.soundEnabled
        )
        evaluateCleanup()
    }

    func evaluateCleanup() {
        let ready = settings.cleanupOnboardingStep == nil
        cleanup.update(volumes: trackedVolumes, thresholds: settings.alertThresholds,
                       configuration: ready && settings.cleanupEnabled ? settings.cleanupConfiguration : nil,
                       quickRecovery: ready && settings.quickRecoveryEnabled ? settings.cleanupConfiguration : nil,
                       sound: settings.soundEnabled)
    }
}
