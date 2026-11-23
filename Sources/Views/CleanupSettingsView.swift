import SwiftUI
import UserNotifications

struct CleanupSettingsView: View {
    var monitor: DiskMonitorService
    @State private var model = ""
    @State private var executablePath = ""
    @State private var connectionMessage = ""
    @State private var check: Task<Void, Never>?
    @State private var notificationStatus: String?

    private var settings: SettingsManager { monitor.settings }

    var body: some View {
        Form {
            Section {
                Toggle(.Cleanup.quickToggle, isOn: quickRecovery)
            } header: {
                Text(.Cleanup.quickHeader)
            } footer: {
                Text(.Cleanup.quickDescription)
            }

            Section {
                Toggle(.Cleanup.suggestionsToggle, isOn: enabled)
            } footer: {
                Text(.Cleanup.suggestionsDescription)
            }

            Section(.Cleanup.agentHeader) {
                Picker(.Cleanup.cli, selection: provider) {
                    ForEach(CleanupAgent.allCases) { agent in
                        Text(agent.name).tag(agent)
                    }
                }

                TextField(.Cleanup.model, text: $model, prompt: Text(settings.cleanupAgent.defaultModel))
                TextField(.Cleanup.executablePath, text: $executablePath, prompt: Text(.Cleanup.detectAutomatically))

                HStack {
                    Button(.Cleanup.saveAndCheck, action: saveAndCheck)
                    if !connectionMessage.isEmpty {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(.Cleanup.allowNotifications) {
                    Task { await requestNotifications() }
                }
                Button(.Cleanup.openNotifications) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                if let notificationStatus {
                    Text(notificationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(.sectionNotifications)
            } footer: {
                Text(.Cleanup.notificationDescription)
            }

            Section(.Cleanup.diskAccess) {
                Text(.Cleanup.diskAccessDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(.Cleanup.openDiskAccess) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadFields)
        .onSubmit(saveAndCheck)
        .task { await refreshNotificationStatus() }
    }

    private var quickRecovery: Binding<Bool> {
        Binding(get: { settings.quickRecoveryEnabled }, set: { enabled in
            if enabled { saveFields() }
            monitor.setQuickRecoveryEnabled(enabled)
            if enabled { Task { await requestNotifications() } }
        })
    }

    private var enabled: Binding<Bool> {
        Binding(get: { settings.cleanupEnabled }, set: { enabled in
            if enabled { saveFields() }
            settings.cleanupEnabled = enabled
            settings.save()
            if enabled {
                Task {
                    await requestNotifications()
                    monitor.evaluateCleanup()
                }
            } else {
                monitor.evaluateCleanup()
            }
        })
    }

    private var provider: Binding<CleanupAgent> {
        Binding(get: { settings.cleanupAgent }, set: { agent in
            saveFields()
            settings.cleanupAgent = agent
            settings.save()
            loadFields()
            monitor.evaluateCleanup()
        })
    }

    private func loadFields() {
        check?.cancel()
        connectionMessage = ""
        model = settings.cleanupModel(for: settings.cleanupAgent)
        executablePath = settings.cleanupExecutable(for: settings.cleanupAgent)
    }

    private func saveFields() {
        settings.setCleanupModel(model, for: settings.cleanupAgent)
        settings.setCleanupExecutable(executablePath, for: settings.cleanupAgent)
    }

    private func saveAndCheck() {
        saveFields()
        monitor.evaluateCleanup()
        check?.cancel()
        connectionMessage = String(localized: .Cleanup.checking)
        let configuration = settings.cleanupConfiguration
        check = Task {
            do {
                try await CleanupAgentRunner().checkConnection(configuration)
                guard !Task.isCancelled else { return }
                connectionMessage = String(localized: .Cleanup.signedIn(configuration.agent.name))
            } catch {
                guard !Task.isCancelled else { return }
                connectionMessage = ((error as? CleanupScanError) ?? .scanFailed).message(for: configuration.agent)
            }
        }
    }

    private func requestNotifications() async {
        await monitor.notifications.requestPermission()
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings()
        switch status.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = status.alertSetting == .enabled
                ? String(localized: .Cleanup.notificationsAllowed)
                : String(localized: .Cleanup.desktopAlertsDisabled)
        case .denied:
            notificationStatus = String(localized: .Cleanup.notificationsOff)
        default:
            notificationStatus = nil
        }
    }
}
