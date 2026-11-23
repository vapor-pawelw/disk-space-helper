import Foundation

enum CleanupOnboardingStep: String {
    case suggestions
    case quickRecovery
}

@Observable
final class SettingsManager {
    private let defaults: UserDefaults

    // MARK: - Stored Properties (tracked by @Observable)

    /// Empty set means "track all discovered volumes"
    var trackedVolumeURLs: Set<URL>
    var alertThresholds: [AlertThreshold]
    var soundEnabled: Bool
    /// When true, the menu bar shows used % instead of free %
    var showUsedPercentage: Bool

    private(set) var cleanupOnboardingStep: CleanupOnboardingStep?
    var quickRecoveryEnabled: Bool
    var cleanupEnabled: Bool
    var cleanupAgent: CleanupAgent
    private var cleanupModels: [String: String]
    private var cleanupPaths: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "soundEnabled": true,
            "showUsedPercentage": false,
        ])

        // Load stored values into observable properties
        if let data = defaults.data(forKey: "trackedVolumeURLs"),
           let urls = try? JSONDecoder().decode(Set<URL>.self, from: data)
        {
            trackedVolumeURLs = urls
        } else {
            trackedVolumeURLs = []
        }

        if let data = defaults.data(forKey: "alertThresholds"),
           let thresholds = try? JSONDecoder().decode([AlertThreshold].self, from: data)
        {
            alertThresholds = thresholds
        } else {
            alertThresholds = AlertThreshold.defaultThresholds
        }

        soundEnabled = defaults.bool(forKey: "soundEnabled")
        showUsedPercentage = defaults.bool(forKey: "showUsedPercentage")
        let onboardingKey = defaults.string(forKey: "cleanupOnboardingStep")
        cleanupOnboardingStep = CleanupOnboardingStep(rawValue: onboardingKey ?? CleanupOnboardingStep.suggestions.rawValue)
        quickRecoveryEnabled = defaults.bool(forKey: "quickRecoveryEnabled")
        cleanupEnabled = defaults.bool(forKey: "cleanupEnabled")
        cleanupAgent = CleanupAgent(rawValue: defaults.string(forKey: "cleanupAgent") ?? "") ?? .codex
        cleanupModels = defaults.dictionary(forKey: "cleanupModels") as? [String: String] ?? [:]
        cleanupPaths = defaults.dictionary(forKey: "cleanupPaths") as? [String: String] ?? [:]
    }

    // MARK: - Persistence

    func save() {
        if let data = try? JSONEncoder().encode(trackedVolumeURLs) {
            defaults.set(data, forKey: "trackedVolumeURLs")
        }
        if let data = try? JSONEncoder().encode(alertThresholds) {
            defaults.set(data, forKey: "alertThresholds")
        }
        defaults.set(soundEnabled, forKey: "soundEnabled")
        defaults.set(showUsedPercentage, forKey: "showUsedPercentage")
        defaults.set(quickRecoveryEnabled, forKey: "quickRecoveryEnabled")
        defaults.set(cleanupEnabled, forKey: "cleanupEnabled")
        defaults.set(cleanupAgent.rawValue, forKey: "cleanupAgent")
        defaults.set(cleanupModels, forKey: "cleanupModels")
        defaults.set(cleanupPaths, forKey: "cleanupPaths")
    }

    var cleanupConfiguration: CleanupAgentConfiguration {
        cleanupConfiguration(for: cleanupAgent)
    }

    func cleanupConfiguration(for agent: CleanupAgent) -> CleanupAgentConfiguration {
        let model = cleanupModel(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(agent: agent, model: model.isEmpty ? agent.defaultModel : model,
                     executablePath: cleanupExecutable(for: agent))
    }

    @discardableResult
    func finishCleanupOnboardingStep(_ step: CleanupOnboardingStep, enableWith agent: CleanupAgent?) -> Bool {
        guard cleanupOnboardingStep == step else { return false }
        if let agent {
            cleanupAgent = agent
            switch step {
            case .suggestions: cleanupEnabled = true
            case .quickRecovery: quickRecoveryEnabled = true
            }
            save()
        }
        let next: CleanupOnboardingStep? = step == .suggestions ? .quickRecovery : nil
        defaults.set(next?.rawValue ?? "complete", forKey: "cleanupOnboardingStep")
        cleanupOnboardingStep = next
        return true
    }

    func cleanupModel(for agent: CleanupAgent) -> String {
        cleanupModels[agent.rawValue] ?? agent.defaultModel
    }

    func setCleanupModel(_ model: String, for agent: CleanupAgent) {
        cleanupModels[agent.rawValue] = model
        save()
    }

    func cleanupExecutable(for agent: CleanupAgent) -> String {
        cleanupPaths[agent.rawValue] ?? ""
    }

    func setCleanupExecutable(_ path: String, for agent: CleanupAgent) {
        cleanupPaths[agent.rawValue] = path
        save()
    }

    // MARK: - First Launch

    var isFirstLaunch: Bool {
        !defaults.bool(forKey: "hasLaunchedBefore")
    }

    func markLaunched() {
        defaults.set(true, forKey: "hasLaunchedBefore")
    }
}
