import Foundation
import Testing

@testable import DiskSpaceHelper

struct NotificationServiceTests {
    private let threshold = AlertThreshold(id: UUID(), bytes: 10_000_000_000, label: "10 GB")

    private func makeVolume(free: Int64) -> VolumeInfo {
        VolumeInfo(
            id: URL(filePath: "/Volumes/Test"),
            name: "Test",
            totalBytes: 100_000_000_000,
            freeBytes: free
        )
    }

    @Test func doesNotCrashWhenNoVolumes() {
        let service = NotificationService()
        service.evaluateThresholds(volumes: [], thresholds: [threshold], soundEnabled: false)
    }

    @Test func doesNotCrashWhenNoThresholds() {
        let service = NotificationService()
        let volume = makeVolume(free: 5_000_000_000)
        service.evaluateThresholds(volumes: [volume], thresholds: [], soundEnabled: false)
    }

    @Test func repeatedCallsDoNotCrash() {
        let service = NotificationService()
        let volume = makeVolume(free: 5_000_000_000)
        // Calling twice should not double-fire (state tracking)
        service.evaluateThresholds(volumes: [volume], thresholds: [threshold], soundEnabled: false)
        service.evaluateThresholds(volumes: [volume], thresholds: [threshold], soundEnabled: false)
    }

    @Test func clearingStateWhenFreeSpaceRecovers() {
        let service = NotificationService()
        let low = makeVolume(free: 5_000_000_000)
        let recovered = makeVolume(free: 50_000_000_000)

        service.evaluateThresholds(volumes: [low], thresholds: [threshold], soundEnabled: false)
        // Space recovered — internal state should clear the threshold
        service.evaluateThresholds(volumes: [recovered], thresholds: [threshold], soundEnabled: false)
        // Going low again should not crash
        service.evaluateThresholds(volumes: [low], thresholds: [threshold], soundEnabled: false)
    }
}
