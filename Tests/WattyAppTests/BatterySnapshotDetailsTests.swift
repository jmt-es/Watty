import XCTest
@testable import Watty
import WattyCore

final class BatterySnapshotDetailsTests: XCTestCase {
    private func fullSnapshot() -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date()
        snapshot.cycleCount = 257
        snapshot.condition = "Normal"
        snapshot.maximumCapacityPercent = 89
        snapshot.adapterRatedWatts = 70
        snapshot.adapterDescription = "USB-C"
        snapshot.powerMode = .lowPower
        return snapshot
    }

    func testEssentialsSnapshotKeepsTheDetailsFromTheLastFullRead() {
        var essentials = BatterySnapshot.empty
        essentials.lastUpdated = Date()
        essentials.level = 64

        let merged = essentials.fillingMissingDetails(from: fullSnapshot())

        XCTAssertEqual(merged.level, 64)
        XCTAssertEqual(merged.cycleCount, 257)
        XCTAssertEqual(merged.condition, "Normal")
        XCTAssertEqual(merged.maximumCapacityPercent, 89)
        XCTAssertEqual(merged.adapterRatedWatts, 70)
        XCTAssertEqual(merged.adapterDescription, "USB-C")
        XCTAssertEqual(merged.powerMode, .lowPower)
    }

    func testFreshDetailsWinOverTheOnesFromTheLastRead() {
        var fresh = BatterySnapshot.empty
        fresh.lastUpdated = Date()
        fresh.cycleCount = 258
        fresh.powerMode = .highPower

        let merged = fresh.fillingMissingDetails(from: fullSnapshot())

        XCTAssertEqual(merged.cycleCount, 258)
        XCTAssertEqual(merged.powerMode, .highPower)
        XCTAssertEqual(merged.condition, "Normal")
    }
}
