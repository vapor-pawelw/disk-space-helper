import Foundation

struct VolumeInfo: Identifiable, Hashable {
    let id: URL
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 { totalBytes - freeBytes }
    var freePercentage: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) * 100.0 : 0 }
    var usedPercentage: Double { 100.0 - freePercentage }
}
