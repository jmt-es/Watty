import XCTest
@testable import Watty
import WattyCore

@MainActor
final class BatteryModelNetFlowTests: XCTestCase {
    private final class ScriptedService: TelemetryProviding {
        var template: BatterySnapshot

        init(_ template: BatterySnapshot) {
            self.template = template
        }

        func fetchSnapshot(depth: SnapshotDepth, forceDetails: Bool) async -> BatterySnapshot {
            var snapshot = template
            snapshot.lastUpdated = Date()
            return snapshot
        }

        func fetchSystemStats() async -> SystemStats {
            SystemStats(date: Date(), cpu: nil, memory: nil, temperature: nil)
        }

        func fetchEnergySample() async -> EnergySample {
            .empty
        }

        func setPowerMode(_ mode: PowerMode) async -> ServiceActionResult {
            ServiceActionResult(reason: .applied(mode), resultingMode: mode)
        }

        func openBatterySettings() {}
    }

    private func pluggedInSnapshot(watts: Double?, charging: Bool = true, adapter: Bool = true) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date()
        snapshot.level = 18
        snapshot.isCharging = charging
        snapshot.powerSource = adapter ? .adapter : .battery
        snapshot.timeToFullMinutes = 579
        snapshot.adapterRatedWatts = 20
        snapshot.batteryPowerWatts = watts
        return snapshot
    }

    private func store(fallingFor minutes: Int, adapter: Bool = true) -> BatteryHistoryStore {
        let store = BatteryHistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("watty-model-test-\(UUID().uuidString)")
                .appendingPathComponent(BatteryHistoryStore.fileName),
            writesEnabled: false
        )
        let now = Date()
        for minute in 0...minutes {
            store.record(
                level: 40 - minute,
                isCharging: adapter,
                onAdapter: adapter,
                at: now.addingTimeInterval(-Double(minutes - minute) * 60 - 5)
            )
        }
        return store
    }

    private func model(snapshot: BatterySnapshot, store: BatteryHistoryStore) -> BatteryModel {
        BatteryModel(service: ScriptedService(snapshot), historyStore: store, observesPowerEvents: false)
    }

    private func waitForFirstSnapshot(of model: BatteryModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.snapshot.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.snapshot.isEmpty)
    }

    func testARestartKeepsTheDrainEvidenceFromTheStoredHistory() async throws {
        let model = model(snapshot: pluggedInSnapshot(watts: -18), store: store(fallingFor: 8))

        try await waitForFirstSnapshot(of: model)

        XCTAssertEqual(model.snapshot.netFlow.flow, .draining)
        XCTAssertEqual(model.snapshot.chargeState, .pluggedInDraining)
        XCTAssertEqual(model.snapshot.reportedChargeState, .charging)
    }

    func testTheMeasuredReadingsAreNeverReplacedByTheEstimate() async throws {
        let model = model(snapshot: pluggedInSnapshot(watts: 4.8), store: store(fallingFor: 8))

        try await waitForFirstSnapshot(of: model)

        XCTAssertEqual(model.snapshot.batteryPowerWatts, 4.8)
        XCTAssertEqual(model.snapshot.chargeState, .pluggedInDraining)
    }

    func testWithoutHistoryTheFirstReadingStaysWithWhatMacOSReports() async throws {
        let model = model(snapshot: pluggedInSnapshot(watts: -18), store: store(fallingFor: 0))

        try await waitForFirstSnapshot(of: model)

        XCTAssertNil(model.snapshot.netFlow.flow)
        XCTAssertEqual(model.snapshot.chargeState, .charging)
    }

    func testAFallOnBatteryInTheHistoryIsNotEvidenceOfAPluggedInDrain() async throws {
        let model = model(snapshot: pluggedInSnapshot(watts: 30), store: store(fallingFor: 8, adapter: false))

        try await waitForFirstSnapshot(of: model)

        XCTAssertNotEqual(model.snapshot.netFlow.flow, .draining)
        XCTAssertEqual(model.snapshot.chargeState, .charging)
    }

    func testOnBatteryTheStateStaysOnBattery() async throws {
        let model = model(snapshot: pluggedInSnapshot(watts: -9, charging: false, adapter: false), store: store(fallingFor: 8, adapter: false))

        try await waitForFirstSnapshot(of: model)

        XCTAssertEqual(model.snapshot.netFlow.flow, .draining)
        XCTAssertEqual(model.snapshot.chargeState, .onBattery)
    }

    func testTheDrainPeriodsOfTheStoredHistoryAreAvailableAtLaunch() {
        let model = model(snapshot: pluggedInSnapshot(watts: -18), store: store(fallingFor: 30))

        XCTAssertEqual(model.drainPeriods.count, 1)
    }
}
