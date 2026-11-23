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

    @Test func localizableMenuAndCLISignInStringsSubstituteArguments() {
        let volume = String(localized: .volumeDescription("Macintosh HD", "190 GB", "200 GB", "10 GB", "5%"))
        let signIn = String(localized: .Cleanup.signedIn("Codex"))
        let paths = String(localized: .Cleanup.paths("3"))

        #expect(volume == "Macintosh HD: 190 GB/200 GB — 10 GB free (5%)")
        #expect(signIn == "Codex is installed and signed in.")
        #expect(paths == "Paths (3)")
    }

    @Test func defaultThresholds() {
        let settings = SettingsManager(defaults: makeSuite())
        #expect(settings.alertThresholds.count == AlertThreshold.defaultThresholds.count)
    }

    @Test func defaultSoundEnabled() {
        let settings = SettingsManager(defaults: makeSuite())
        #expect(settings.soundEnabled == true)
    }

    @Test func defaultShowUsedPercentage() {
        let settings = SettingsManager(defaults: makeSuite())
        #expect(settings.showUsedPercentage == false)
    }

    @Test func defaultTrackedVolumeURLsIsEmpty() {
        let settings = SettingsManager(defaults: makeSuite())
        #expect(settings.trackedVolumeURLs.isEmpty)
    }

    @Test func isFirstLaunchThenMarkLaunched() {
        let settings = SettingsManager(defaults: makeSuite())
        #expect(settings.isFirstLaunch)
        settings.markLaunched()
        #expect(settings.isFirstLaunch == false)
    }

    @Test func saveAndReloadThresholds() {
        let defaults = makeSuite()
        let settings = SettingsManager(defaults: defaults)
        let custom = [AlertThreshold(id: UUID(), bytes: 42, label: "42 B")]
        settings.alertThresholds = custom
        settings.save()

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.alertThresholds == custom)
    }
}
