import Foundation

struct VolumeInfo: Identifiable, Hashable {
    let id: URL
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64
    let cleanupFreeBytes: Int64

    init(id: URL, name: String, totalBytes: Int64, freeBytes: Int64, cleanupFreeBytes: Int64? = nil) {
        self.id = id
        self.name = name
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.cleanupFreeBytes = cleanupFreeBytes ?? freeBytes
    }

    var usedBytes: Int64 { totalBytes - freeBytes }
    var freePercentage: Double { totalBytes > 0 ? Double(freeBytes) / Double(totalBytes) * 100.0 : 0 }
    var usedPercentage: Double { 100.0 - freePercentage }
}
