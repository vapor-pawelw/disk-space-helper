import Foundation
import Testing

@testable import DiskSpaceHelper

struct SettingsManagerTests {
    /// Uses a fresh volatile UserDefaults suite so tests don't pollute each other
    /// or the real app settings.
    private func makeSuite() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultThresholds() {
        let settings = SettingsManager()
        #expect(settings.alertThresholds.count == AlertThreshold.defaultThresholds.count)
    }

    @Test func defaultSoundEnabled() {
        let settings = SettingsManager()
        #expect(settings.soundEnabled == true)
    }

    @Test func defaultShowUsedPercentage() {
        let settings = SettingsManager()
        #expect(settings.showUsedPercentage == false)
    }

    @Test func defaultTrackedVolumeURLsIsEmpty() {
        let settings = SettingsManager()
        #expect(settings.trackedVolumeURLs.isEmpty)
    }

    @Test func isFirstLaunchThenMarkLaunched() {
        let settings = SettingsManager()
        // Can't assert isFirstLaunch reliably since it reads shared UserDefaults,
        // but markLaunched should not crash
        settings.markLaunched()
        #expect(settings.isFirstLaunch == false)
    }

    @Test func saveAndReloadThresholds() {
        let settings = SettingsManager()
        let custom = [AlertThreshold(id: UUID(), bytes: 42, label: "42 B")]
        settings.alertThresholds = custom
        settings.save()

        let reloaded = SettingsManager()
        #expect(reloaded.alertThresholds == custom)
    }
}
