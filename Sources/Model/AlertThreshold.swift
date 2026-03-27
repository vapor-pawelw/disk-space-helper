import Foundation

struct AlertThreshold: Identifiable, Codable, Hashable {
    let id: UUID
    var bytes: Int64
    var label: String

    static let defaultThresholds: [AlertThreshold] = [
        AlertThreshold(id: UUID(), bytes: 10_000_000_000, label: "10 GB"),
        AlertThreshold(id: UUID(), bytes: 1_000_000_000, label: "1 GB"),
    ]
}
