import SwiftUI

struct MenuContentView: View {
    var monitor: DiskMonitorService
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

    private func volumeDescription(_ volume: VolumeInfo) -> String {
        let used = formatBytes(volume.usedBytes)
        let total = formatBytes(volume.totalBytes)
        let free = formatBytes(volume.freeBytes)
        let pct = "\(Int(volume.freePercentage))%"
        return String(localized: .volumeDescription(volume.name, used, total, free, pct))
    }
}
