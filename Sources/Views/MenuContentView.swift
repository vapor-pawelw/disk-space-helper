import SwiftUI

struct MenuContentView: View {
    var monitor: DiskMonitorService
    var showCleanup: (URL?) -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if monitor.trackedVolumes.isEmpty {
            Text(.noVolumesFound)
                .foregroundStyle(.secondary)
        } else {
            ForEach(monitor.trackedVolumes) { volume in
                Text(volumeDescription(volume))
            }
        }

        if let summary = monitor.cleanup.quickRecoverySummary {
            Text(summary)
        }

        if monitor.settings.cleanupEnabled {
            let cleanup = monitor.cleanup
            Divider()
            if !cleanup.reviewVolumes.isEmpty {
                Button(cleanup.needsAttention ? .Cleanup.menuNeedsAttention : .Cleanup.menuReview) {
                    showCleanup(nil)
                }
            }
            if monitor.settings.cleanupOnboardingStep == nil {
                if monitor.trackedVolumes.count > 1 {
                    Menu(.Cleanup.menuScan) {
                        ForEach(monitor.trackedVolumes) { volume in
                            Button(volume.name) { scan(volume) }
                        }
                    }
                } else if let volume = monitor.trackedVolumes.first {
                    Button(.Cleanup.menuScan) { scan(volume) }
                }
            }
        }

        Divider()

        Button(.menuSettings) {
            openSettings()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(.menuQuit) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func scan(_ volume: VolumeInfo) {
        monitor.cleanup.scanNow(volume.id)
        showCleanup(volume.id)
    }

    private func volumeDescription(_ volume: VolumeInfo) -> String {
        let used = formatBytes(volume.usedBytes)
        let total = formatBytes(volume.totalBytes)
        let free = formatBytes(volume.freeBytes)
        let pct = "\(Int(volume.freePercentage))%"
        return String(localized: .volumeDescription(volume.name, used, total, free, pct))
    }
}
