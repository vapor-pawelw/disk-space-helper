import ServiceManagement
import SwiftUI

@main
struct DiskSpaceHelperApp: App {
    @State private var monitor = DiskMonitorService()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
                .task {
                    await performFirstLaunchIfNeeded()
                }
        } label: {
            Image(systemName: "internaldrive")
            Text(monitor.menuBarTitle)
        }

        Settings {
            SettingsView(monitor: monitor)
        }
    }

    private func performFirstLaunchIfNeeded() async {
        guard monitor.settings.isFirstLaunch else { return }

        await monitor.notifications.requestPermission()

        // Enable launch at login by default
        try? SMAppService.mainApp.register()

        monitor.settings.markLaunched()
    }
}
