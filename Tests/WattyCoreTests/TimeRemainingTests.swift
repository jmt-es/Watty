import XCTest
@testable import WattyCore

final class TimeRemainingTests: XCTestCase {
    private func snapshot(
        charging: Bool = false,
        adapter: Bool = false,
        full: Bool = false,
        finishing: Bool = false,
        level: Int = 60,
        toFull: Int? = nil,
        toEmpty: Int? = nil
    ) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date()
        snapshot.level = level
        snapshot.isCharging = charging
        snapshot.isFullyCharged = full
        snapshot.isFinishingCharge = finishing
        snapshot.powerSource = adapter ? .adapter : .battery
        snapshot.timeToFullMinutes = toFull
        snapshot.timeToEmptyMinutes = toEmpty
        return snapshot
    }

    func testBeforeTheFirstReadingItIsWaiting() {
        XCTAssertEqual(BatterySnapshot.empty.timeRemaining, .waitingForFirstReading)
    }

    func testChargingReportsTheTimeToFullWhenKnown() {
        XCTAssertEqual(snapshot(charging: true, adapter: true, toFull: 75).timeRemaining, .untilFull(minutes: 75))
    }

    func testChargingWithoutAnEstimateIsCalculatingUntilItFinishes() {
        XCTAssertEqual(snapshot(charging: true, adapter: true).timeRemaining, .calculatingUntilFull)
        XCTAssertEqual(snapshot(charging: true, adapter: true, finishing: true).timeRemaining, .finishingCharge)
        XCTAssertEqual(snapshot(charging: true, adapter: true, level: 100).timeRemaining, .finishingCharge)
    }

    func testPluggedInStatesDoNotEstimateAnything() {
        XCTAssertEqual(snapshot(adapter: true, full: true).timeRemaining, .fullyCharged)
        XCTAssertEqual(snapshot(adapter: true, level: 80).timeRemaining, .runningFromAdapter)
    }

    func testOnBatteryReportsTheTimeLeftWhenKnown() {
        XCTAssertEqual(snapshot(toEmpty: 192).timeRemaining, .untilEmpty(minutes: 192))
        XCTAssertEqual(snapshot().timeRemaining, .calculatingUntilEmpty)
    }

    func testDrainingOnTheAdapterNamesTheAdapterThatCannotKeepUp() {
        var draining = snapshot(charging: true, adapter: true, toFull: 579)
        draining.adapterRatedWatts = 20
        draining.netFlow = NetFlowEstimate(flow: .draining, averageBatteryWatts: -18)

        XCTAssertEqual(draining.timeRemaining, .adapterCannotKeepUp(ratedWatts: 20))
        XCTAssertEqual(draining.timeRemainingText, "The 20 W adapter can't keep up")
    }

    func testDrainingWhileMacOSIsNotChargingSaysTheBatteryIsInUse() {
        var draining = snapshot(adapter: true, level: 72)
        draining.adapterRatedWatts = 96
        draining.netFlow = NetFlowEstimate(flow: .draining, averageBatteryWatts: -9)

        XCTAssertEqual(draining.chargeState, .pluggedInDraining)
        XCTAssertEqual(draining.timeRemaining, .usingBatteryOnAdapter)
        XCTAssertEqual(draining.timeRemainingText, "Using the battery while plugged in")
    }

    func testDrainingOnTheAdapterWithoutARatingUsesAGenericSentence() {
        for rated in [nil, 0, -1] as [Int?] {
            var draining = snapshot(charging: true, adapter: true, toFull: 579)
            draining.adapterRatedWatts = rated
            draining.netFlow = NetFlowEstimate(flow: .draining)

            XCTAssertEqual(draining.timeRemaining, .adapterCannotKeepUp(ratedWatts: nil), "\(String(describing: rated))")
            XCTAssertEqual(draining.timeRemainingText, "The adapter can't keep up")
        }
    }

    func testTheOtherFlowsKeepTheEstimateMacOSGave() {
        for flow in [NetFlow.charging, .holding] {
            var charging = snapshot(charging: true, adapter: true, toFull: 75)
            charging.netFlow = NetFlowEstimate(flow: flow)

            XCTAssertEqual(charging.timeRemaining, .untilFull(minutes: 75), "\(flow)")
        }
    }

    func testOnBatteryTheDrainingFlowDoesNotReplaceTheTimeLeft() {
        var onBattery = snapshot(toEmpty: 192)
        onBattery.netFlow = NetFlowEstimate(flow: .draining, averageBatteryWatts: -10)

        XCTAssertEqual(onBattery.timeRemaining, .untilEmpty(minutes: 192))
    }

    func testTheEnglishTextMatchesTheStructure() {
        XCTAssertEqual(TimeRemaining.untilFull(minutes: 75).text, "1:15 to full")
        XCTAssertEqual(TimeRemaining.untilEmpty(minutes: 5).text, "0:05 left")
        XCTAssertEqual(TimeRemaining.finishingCharge.text, "Finishing charge")
        XCTAssertEqual(TimeRemaining.calculatingUntilFull.text, "Calculating time to full")
        XCTAssertEqual(TimeRemaining.calculatingUntilEmpty.text, "Calculating time left")
        XCTAssertEqual(TimeRemaining.fullyCharged.text, "Fully charged")
        XCTAssertEqual(TimeRemaining.runningFromAdapter.text, "Running from adapter")
        XCTAssertEqual(TimeRemaining.adapterCannotKeepUp(ratedWatts: 20).text, "The 20 W adapter can't keep up")
        XCTAssertEqual(TimeRemaining.adapterCannotKeepUp(ratedWatts: nil).text, "The adapter can't keep up")
        XCTAssertEqual(TimeRemaining.waitingForFirstReading.text, "Waiting for first reading")
    }

    func testTheSnapshotTextIsTheTextOfItsTimeRemaining() {
        let samples = [
            BatterySnapshot.empty,
            snapshot(charging: true, adapter: true, toFull: 30),
            snapshot(charging: true, adapter: true),
            snapshot(adapter: true, full: true),
            snapshot(adapter: true),
            snapshot(toEmpty: 90),
            snapshot()
        ]
        for sample in samples {
            XCTAssertEqual(sample.timeRemainingText, sample.timeRemaining.text)
        }
    }
}
