import Foundation
import Testing

@testable import DiskSpaceHelper

struct VolumeInfoTests {
    private func makeVolume(total: Int64, free: Int64) -> VolumeInfo {
        VolumeInfo(
            id: URL(filePath: "/Volumes/Test"),
            name: "Test",
            totalBytes: total,
            freeBytes: free
        )
    }

    @Test func usedBytes() {
        let volume = makeVolume(total: 1000, free: 300)
        #expect(volume.usedBytes == 700)
    }

    @Test func freePercentage() {
        let volume = makeVolume(total: 200, free: 50)
        #expect(volume.freePercentage == 25.0)
    }

    @Test func usedPercentage() {
        let volume = makeVolume(total: 200, free: 50)
        #expect(volume.usedPercentage == 75.0)
    }

    @Test func zeroTotalReturnsZeroPercentage() {
        let volume = makeVolume(total: 0, free: 0)
        #expect(volume.freePercentage == 0)
        #expect(volume.usedPercentage == 100.0)
    }
}
