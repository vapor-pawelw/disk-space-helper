import SwiftUI

struct MenuBarLabel: View {
    var monitor: DiskMonitorService

    var body: some View {
        if let pct = monitor.lowestFreePercentage {
            let display = monitor.settings.showUsedPercentage ? Int(100 - pct) : Int(pct)
            Label("\(display)%", systemImage: "internaldrive")
        } else {
            Image(systemName: "internaldrive")
        }
    }
}
