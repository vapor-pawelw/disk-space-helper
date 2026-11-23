import Foundation
import Testing

@testable import DiskSpaceHelper

struct CleanupOnboardingTests {
    @Test func freshInstallLetsUserChooseEachFeatureSeparately() {
        let name = "cleanup-onboarding-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.cleanupOnboardingStep == .suggestions)
        #expect(!settings.cleanupEnabled && !settings.quickRecoveryEnabled)

        settings.finishCleanupOnboardingStep(.suggestions, enableWith: .claude)
        #expect(settings.cleanupEnabled && !settings.quickRecoveryEnabled)
        #expect(settings.cleanupAgent == .claude)
        let resumed = SettingsManager(defaults: defaults)
        #expect(resumed.cleanupOnboardingStep == .quickRecovery)

        resumed.finishCleanupOnboardingStep(.quickRecovery, enableWith: nil)
        let complete = SettingsManager(defaults: defaults)
        #expect(complete.cleanupOnboardingStep == nil)
        #expect(complete.cleanupEnabled && !complete.quickRecoveryEnabled)
    }

    @Test func skippingUpgradeSetupPreservesExistingChoices() {
        let name = "cleanup-onboarding-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "hasLaunchedBefore")
        defaults.set(true, forKey: "quickRecoveryEnabled")
        defaults.set("claude", forKey: "cleanupAgent")

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.cleanupOnboardingStep == .suggestions)
        settings.finishCleanupOnboardingStep(.suggestions, enableWith: nil)
        settings.finishCleanupOnboardingStep(.quickRecovery, enableWith: nil)

        let complete = SettingsManager(defaults: defaults)
        #expect(complete.cleanupOnboardingStep == nil)
        #expect(!complete.cleanupEnabled && complete.quickRecoveryEnabled)
        #expect(complete.cleanupAgent == .claude)
    }
}
