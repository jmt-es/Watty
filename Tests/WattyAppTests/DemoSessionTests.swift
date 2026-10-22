import XCTest
@testable import Watty
import WattyCore

@MainActor
final class DemoSessionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        ArgumentDomainSandbox.install(in: self)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testTheModelShowsTheChargingScenarioInsteadOfReadingTheMachine() async throws {
        let model = DemoSession.makeModel(for: .charging)

        try await waitUntil { !model.snapshot.isEmpty && model.stats != nil && !model.energySample.isEmpty }

        XCTAssertEqual(model.snapshot.level, DemoSnapshot.chargingLevel)
        XCTAssertEqual(model.snapshot.chargeState, .charging)
        XCTAssertEqual(model.stats?.cpu?.totalPercent ?? 0, DemoStats.profile(for: .charging).cpu.totalPercent, accuracy: 0.001)
        XCTAssertTrue(model.energySample.consumers.contains { $0.name == "Safari" })
        XCTAssertTrue(model.availablePowerModes.contains(.highPower))
    }

    func testTheDrainingScenarioReadsAsPluggedInAndDrainingAtOnce() async throws {
        let model = DemoSession.makeModel(for: .draining)

        try await waitUntil { !model.snapshot.isEmpty }

        XCTAssertEqual(model.snapshot.chargeState, .pluggedInDraining)
        XCTAssertEqual(model.snapshot.reportedChargeState, .charging)
        XCTAssertEqual(model.snapshot.timeRemaining, .adapterCannotKeepUp(ratedWatts: 20))
        XCTAssertEqual(model.snapshot.batteryPowerWatts, -18.3)
        XCTAssertEqual(model.drainPeriods.count, 1)
    }

    func testTheChargingAndBatteryScenariosKeepTheirStates() async throws {
        let charging = DemoSession.makeModel(for: .charging)
        let onBattery = DemoSession.makeModel(for: .battery)

        try await waitUntil { !charging.snapshot.isEmpty && !onBattery.snapshot.isEmpty }

        XCTAssertEqual(charging.snapshot.chargeState, .charging)
        XCTAssertEqual(charging.snapshot.netFlow.flow, .charging)
        XCTAssertEqual(onBattery.snapshot.chargeState, .onBattery)
        XCTAssertEqual(onBattery.snapshot.netFlow.flow, .draining)
    }

    func testTheModelStartsWithAFullDayOfBatteryHistoryAndTenMinutesOfStats() throws {
        let model = DemoSession.makeModel(for: .charging)

        XCTAssertEqual(model.historySamples.count, DemoBatteryHistory.coveredMinutes + 1)
        XCTAssertGreaterThanOrEqual(model.statsHistory.count, 300)
        let oldest = try XCTUnwrap(model.statsHistory.first?.date)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(oldest), RefreshCadence.statsWindow - 5)
    }

    func testTheDesktopScenarioHasNoBattery() async throws {
        let model = DemoSession.makeModel(for: .desktop)

        try await waitUntil { !model.snapshot.isEmpty }

        XCTAssertFalse(model.hasBattery)
        XCTAssertTrue(model.historySamples.isEmpty)
    }

    func testTheDemoPinsThePanelPreferencesForReproducibleCaptures() {
        _ = DemoSession.makeModel(for: .charging)

        XCTAssertEqual(UserDefaults.standard.object(forKey: PreferenceKey.healthExpanded) as? Bool, false)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: PreferenceKey.batteryChartRange), BatteryChartRange.sixHours.rawValue)
    }
}
