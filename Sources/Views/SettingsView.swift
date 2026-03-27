import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var monitor: DiskMonitorService

    @State private var launchAtLogin: Bool = true

    var body: some View {
        TabView {
            partitionsTab
                .tabItem { Label("Partitions", systemImage: "internaldrive") }

            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
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
                    Text("No internal volumes detected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.volumes) { volume in
                        Toggle(isOn: bindingFor(volume)) {
                            VStack(alignment: .leading) {
                                Text(volume.name)
                                Text("\(formatBytes(volume.freeBytes)) free of \(formatBytes(volume.totalBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Select which partitions to monitor. When none are selected, all are tracked.")
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
            Section("Alert Thresholds") {
                ForEach(monitor.settings.alertThresholds.indices, id: \.self) { index in
                    HStack {
                        TextField("GB", value: Binding(
                            get: { Double(monitor.settings.alertThresholds[index].bytes) / 1_000_000_000 },
                            set: {
                                monitor.settings.alertThresholds[index].bytes = Int64($0 * 1_000_000_000)
                                updateThresholdLabel(at: index)
                                monitor.settings.save()
                            }
                        ), format: .number)
                        .frame(width: 80)

                        Text("GB")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(role: .destructive) {
                            let id = monitor.settings.alertThresholds[index].id
                            monitor.settings.alertThresholds.removeAll { $0.id == id }
                            monitor.settings.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Threshold") {
                    monitor.settings.alertThresholds.append(AlertThreshold(
                        id: UUID(),
                        bytes: 5_000_000_000,
                        label: "5 GB"
                    ))
                    monitor.settings.save()
                }
            }

            Section("Notifications") {
                Toggle("Play sound with alerts", isOn: Binding(
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

    private func updateThresholdLabel(at index: Int) {
        let gb = Double(monitor.settings.alertThresholds[index].bytes) / 1_000_000_000
        monitor.settings.alertThresholds[index].label = gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(newValue)
                    }
            }

            Section {
                Toggle("Show used % instead of free %", isOn: Binding(
                    get: { monitor.settings.showUsedPercentage },
                    set: {
                        monitor.settings.showUsedPercentage = $0
                        monitor.settings.save()
                    }
                ))
            } footer: {
                Text("Controls whether the menu bar shows used or remaining disk space percentage.")
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
