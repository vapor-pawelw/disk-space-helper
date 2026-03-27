import Foundation

private let volumeResourceKeys: Set<URLResourceKey> = [
    .volumeIsInternalKey,
    .volumeIsRemovableKey,
    .volumeIsLocalKey,
    .volumeIsReadOnlyKey,
    .volumeTotalCapacityKey,
    .volumeAvailableCapacityForImportantUsageKey,
    .volumeNameKey,
]

@Observable
final class DiskMonitorService {
    private(set) var volumes: [VolumeInfo] = []
    private var timer: Timer?

    let settings = SettingsManager()
    let notifications = NotificationService()

    init() {
        pollVolumes()
        startMonitoring()
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

    func startMonitoring() {
        pollVolumes()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollVolumes()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func pollVolumes() {
        guard let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeResourceKeys),
            options: [.skipHiddenVolumes]
        ) else { return }

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
                freeBytes: free
            )
        }

        notifications.evaluateThresholds(
            volumes: trackedVolumes,
            thresholds: settings.alertThresholds,
            soundEnabled: settings.soundEnabled
        )
    }
}
