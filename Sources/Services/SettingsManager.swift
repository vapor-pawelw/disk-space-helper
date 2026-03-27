import Foundation

@Observable
final class SettingsManager {
    private let defaults = UserDefaults.standard

    // MARK: - Stored Properties (tracked by @Observable)

    /// Empty set means "track all discovered volumes"
    var trackedVolumeURLs: Set<URL>
    var alertThresholds: [AlertThreshold]
    var soundEnabled: Bool
    /// When true, the menu bar shows used % instead of free %
    var showUsedPercentage: Bool

    init() {
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
    }

    // MARK: - First Launch

    var isFirstLaunch: Bool {
        !defaults.bool(forKey: "hasLaunchedBefore")
    }

    func markLaunched() {
        defaults.set(true, forKey: "hasLaunchedBefore")
    }
}
