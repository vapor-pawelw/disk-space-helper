import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct DiskSpaceHelperApp: App {
    @NSApplicationDelegateAdaptor(DiskSpaceHelperDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: delegate.monitor) { delegate.showCleanup() }
        } label: {
            let needsAttention = delegate.monitor.cleanup.needsAttention
            Image(systemName: needsAttention ? "exclamationmark.triangle" : "internaldrive")
                .help(needsAttention ? Text(.Cleanup.needsAttention) : Text(.Cleanup.applicationTitle))
            Text(delegate.monitor.menuBarTitle)
        }

        Settings {
            SettingsView(monitor: delegate.monitor)
        }
    }
}

@MainActor
final class DiskSpaceHelperDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let monitor = DiskMonitorService()
    private var cleanupWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private let selection = CleanupWindowSelection()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        monitor.notifications.registerCleanupCategory()
        if monitor.settings.isFirstLaunch {
            try? SMAppService.mainApp.register()
            monitor.settings.markLaunched()
            Task {
                await monitor.notifications.requestPermission()
                startApp()
            }
        } else {
            startApp()
        }
    }

    private func startApp() {
        monitor.startMonitoring()
        guard monitor.settings.cleanupOnboardingStep != nil, onboardingWindow == nil else { return }

        let view = CleanupOnboardingFlow(monitor: monitor) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.monitor.applyCleanupSettings()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 548),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: .Onboarding.windowTitle)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        onboardingWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showCleanup(volume: URL? = nil) {
        if let volume {
            selection.volume = monitor.trackedVolumes.first { $0.id.path == volume.path }?.id
        }
        if cleanupWindow == nil {
            let selection = self.selection
            let view = CleanupReviewView(monitor: monitor, selectedVolume: Binding(
                get: { selection.volume }, set: { selection.volume = $0 }
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: .Cleanup.title)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.minSize = NSSize(width: 560, height: 400)
            window.center()
            cleanupWindow = window
        }
        NSApp.activate()
        cleanupWindow?.makeKeyAndOrderFront(nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier == NotificationService.cleanupCategory,
              response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == NotificationService.reviewCleanupAction else { return }
        let url = (content.userInfo["volumePath"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
        await showCleanup(volume: url)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@Observable
private final class CleanupWindowSelection {
    var volume: URL?
}
