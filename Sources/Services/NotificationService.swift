import Foundation
import UserNotifications

final class NotificationService {
    /// Tracks which thresholds have already fired for each volume to avoid repeated alerts.
    /// Key: volume mount URL, Value: set of threshold IDs that have already triggered.
    private var alertedState: [URL: Set<UUID>] = [:]

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func evaluateThresholds(
        volumes: [VolumeInfo],
        thresholds: [AlertThreshold],
        soundEnabled: Bool
    ) {
        for volume in volumes {
            for threshold in thresholds {
                let alreadyAlerted = alertedState[volume.id]?.contains(threshold.id) ?? false

                if volume.freeBytes < threshold.bytes {
                    if !alreadyAlerted {
                        fireNotification(volume: volume, threshold: threshold, sound: soundEnabled)
                        alertedState[volume.id, default: []].insert(threshold.id)
                    }
                } else {
                    alertedState[volume.id]?.remove(threshold.id)
                }
            }
        }
    }

    private func fireNotification(volume: VolumeInfo, threshold: AlertThreshold, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: .notificationTitle)
        content.body = String(localized: .notificationBody(volume.name, threshold.label, formatBytes(volume.freeBytes)))
        if sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "\(volume.id.path)-\(threshold.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
