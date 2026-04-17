import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var monitor: DiskMonitorService

    @State private var launchAtLogin: Bool = true

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(.tabGeneral, systemImage: "gear") }

            partitionsTab
                .tabItem { Label(.tabPartitions, systemImage: "internaldrive") }

            alertsTab
                .tabItem { Label(.tabAlerts, systemImage: "bell") }
        }
        .frame(width: 480, height: 320)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Partitions Tab

    private var partitionsTab: some View {
        Form {
            Section {
                if monitor.volumes.isEmpty {
                    Text(.noVolumesDetected)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.volumes) { volume in
                        Toggle(isOn: bindingFor(volume)) {
                            VStack(alignment: .leading) {
                                Text(volume.name)
                                Text(.partitionsFreeBytes(formatBytes(volume.freeBytes), formatBytes(volume.totalBytes)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text(.partitionsHeader)
            }
        }
        .formStyle(.grouped)
    }

    private func bindingFor(_ volume: VolumeInfo) -> Binding<Bool> {
        Binding(
            get: {
                monitor.settings.trackedVolumeURLs.isEmpty || monitor.settings.trackedVolumeURLs.contains(volume.id)
            },
            set: { isOn in
                if monitor.settings.trackedVolumeURLs.isEmpty {
                    monitor.settings.trackedVolumeURLs = Set(monitor.volumes.map(\.id))
                }
                if isOn {
                    monitor.settings.trackedVolumeURLs.insert(volume.id)
                } else {
                    monitor.settings.trackedVolumeURLs.remove(volume.id)
                }
                if monitor.settings.trackedVolumeURLs == Set(monitor.volumes.map(\.id)) {
                    monitor.settings.trackedVolumeURLs = []
                }
                monitor.settings.save()
            }
        )
    }

    // MARK: - Alerts Tab

    private var alertsTab: some View {
        Form {
            Section(.sectionAlertThresholds) {
                // Iterate by identity, not index — index-based ForEach crashes
                // when the array mutates (e.g. delete) because SwiftUI still
                // holds stale indices.
                ForEach(monitor.settings.alertThresholds) { threshold in
                    HStack {
                        TextField(String(localized: .unitGB), value: thresholdBytesBinding(for: threshold.id), format: .number)
                            .frame(width: 80)

                        Text(.unitGB)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(role: .destructive) {
                            monitor.settings.alertThresholds.removeAll { $0.id == threshold.id }
                            monitor.settings.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button(.addThreshold) {
                    monitor.settings.alertThresholds.append(AlertThreshold(
                        id: UUID(),
                        bytes: 5_000_000_000,
                        label: "5 GB"
                    ))
                    monitor.settings.save()
                }
            }

            Section(.sectionNotifications) {
                Toggle(.playSoundWithAlerts, isOn: Binding(
                    get: { monitor.settings.soundEnabled },
                    set: {
                        monitor.settings.soundEnabled = $0
                        monitor.settings.save()
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private func thresholdBytesBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: {
                guard let threshold = monitor.settings.alertThresholds.first(where: { $0.id == id }) else { return 0 }
                return Double(threshold.bytes) / 1_000_000_000
            },
            set: { newGB in
                guard let index = monitor.settings.alertThresholds.firstIndex(where: { $0.id == id }) else { return }
                monitor.settings.alertThresholds[index].bytes = Int64(newGB * 1_000_000_000)
                monitor.settings.alertThresholds[index].label = newGB.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(newGB)) GB"
                    : String(format: "%.1f GB", newGB)
                monitor.settings.save()
            }
        )
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle(.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }

            Section {
                Toggle(.showUsedPercentage, isOn: Binding(
                    get: { monitor.settings.showUsedPercentage },
                    set: {
                        monitor.settings.showUsedPercentage = $0
                        monitor.settings.save()
                    }
                ))
            } footer: {
                Text(.showUsedPercentageFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}
