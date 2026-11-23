import Foundation
import UserNotifications

final class NotificationService {
    static let cleanupCategory = "DiskCleanup"
    static let reviewCleanupAction = "ReviewCleanup"

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

                if threshold.bytes > 0 && volume.freeBytes <= threshold.bytes {
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

    func registerCleanupCategory() {
        let review = UNNotificationAction(
            identifier: Self.reviewCleanupAction, title: String(localized: .Cleanup.reviewAction), options: [.foreground]
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.cleanupCategory, actions: [review], intentIdentifiers: [])
        ])
    }

    func postCleanupNotification(for volume: URL, message: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: .Cleanup.title)
        content.body = message
        content.categoryIdentifier = Self.cleanupCategory
        content.userInfo["volumePath"] = volume.path
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "cleanup-\(volume.path)", content: content, trigger: nil)
        )
    }

    func postQuickRecoveryNotification(volume: String, message: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: .Cleanup.recoveryTitle)
        content.body = message
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "quick-recovery-\(volume)", content: content, trigger: nil)
        )
    }

    func clearCleanupNotification(for volume: URL) {
        let ids = ["cleanup-\(volume.path)"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
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
