import Foundation

enum CleanupPolicy {
    static func shouldScan(_ volume: VolumeInfo, thresholds: [AlertThreshold]) -> Bool {
        guard volume.totalBytes > 0 else { return false }
        return volume.cleanupFreeBytes <= volume.totalBytes / 100 || thresholds.contains {
            $0.bytes > 0 && volume.freeBytes <= $0.bytes
        }
    }

    static func targetBytes(for volume: VolumeInfo, thresholds: [AlertThreshold]) -> Int64 {
        let fivePercent = volume.totalBytes / 20 + (volume.totalBytes % 20 == 0 ? 0 : 1)
        let warning = thresholds.map(\.bytes).filter { $0 > 0 && $0 < volume.totalBytes }.max() ?? 0
        let aboveWarning = min(warning, volume.totalBytes - 1) + 1
        return max(fivePercent, aboveWarning)
    }
}
