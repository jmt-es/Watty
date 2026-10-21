import XCTest
@testable import Watty
import WattyCore

final class DemoTelemetryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func telemetry(_ scenario: DemoScenario) -> DemoTelemetry {
        DemoTelemetry(scenario: scenario, now: { self.date })
    }

    func testSnapshotsFollowTheScenarioWhateverTheDepth() async {
        for depth in [SnapshotDepth.full, .essentials] {
            let charging = await telemetry(.charging).fetchSnapshot(depth: depth, forceDetails: true)
            let desktop = await telemetry(.desktop).fetchSnapshot(depth: depth, forceDetails: false)

            XCTAssertEqual(charging, DemoSnapshot.make(for: .charging, at: date))
            XCTAssertFalse(desktop.hasBattery)
        }
    }

    func testStatsAndEnergyFollowTheScenario() async {
        let stats = await telemetry(.battery).fetchSystemStats()
        let energy = await telemetry(.battery).fetchEnergySample()

        XCTAssertEqual(stats, DemoStats.current(for: .battery, at: date))
        XCTAssertEqual(energy, DemoEnergy.sample(for: .battery, at: date))
    }

    func testChangingTheEnergyModeIsRememberedWithoutAskingForAPassword() async {
        let telemetry = telemetry(.charging)

        let result = await telemetry.setPowerMode(.highPower)
        let snapshot = await telemetry.fetchSnapshot(depth: .full, forceDetails: false)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.resultingMode, .highPower)
        XCTAssertEqual(snapshot.powerMode, .highPower)
        XCTAssertEqual(snapshot.lowPowerModeActive, false)
    }

    func testEnergyModesStartAutomaticAndAreIndependentBetweenProviders() async {
        let changed = telemetry(.charging)
        _ = await changed.setPowerMode(.lowPower)

        let untouched = await telemetry(.charging).fetchSnapshot(depth: .full, forceDetails: false)

        XCTAssertEqual(untouched.powerMode, .automatic)
    }

    func testOpeningBatterySettingsLeavesTheSystemAlone() {
        telemetry(.charging).openBatterySettings()
    }
}
