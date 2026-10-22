import XCTest
@testable import Watty
import WattyCore

final class LocalizedTextTests: XCTestCase {
    func testChargeStateTitles() {
        XCTAssertEqual(ChargeState.charging.localizedTitle, "Charging")
        XCTAssertEqual(ChargeState.charged.localizedTitle, "Charged")
        XCTAssertEqual(ChargeState.pluggedInNotCharging.localizedTitle, "Plugged in, not charging")
        XCTAssertEqual(ChargeState.pluggedInDraining.localizedTitle, "Plugged in, draining")
        XCTAssertEqual(ChargeState.onBattery.localizedTitle, "On battery")
        XCTAssertEqual(ChargeState.unknown.localizedTitle, "Reading battery")
    }

    func testEveryChargeStateHasADistinctTitle() {
        let states: [ChargeState] = [.charging, .charged, .pluggedInNotCharging, .pluggedInDraining, .onBattery, .unknown]

        XCTAssertEqual(Set(states.map(\.localizedTitle)).count, states.count)
    }

    func testPowerModeTitles() {
        XCTAssertEqual(PowerMode.automatic.localizedTitle, "Auto")
        XCTAssertEqual(PowerMode.lowPower.localizedTitle, "Low")
        XCTAssertEqual(PowerMode.highPower.localizedTitle, "High")
        XCTAssertEqual(PowerMode.automatic.localizedLongTitle, "Automatic")
        XCTAssertEqual(PowerMode.lowPower.localizedLongTitle, "Low Power")
        XCTAssertEqual(PowerMode.highPower.localizedLongTitle, "High Power")
    }

    func testTimeRemainingTexts() {
        XCTAssertEqual(TimeRemaining.untilFull(minutes: 75).localizedText, "1:15 to full")
        XCTAssertEqual(TimeRemaining.untilEmpty(minutes: 5).localizedText, "0:05 left")
        XCTAssertEqual(TimeRemaining.finishingCharge.localizedText, "Finishing charge")
        XCTAssertEqual(TimeRemaining.calculatingUntilFull.localizedText, "Calculating time to full")
        XCTAssertEqual(TimeRemaining.calculatingUntilEmpty.localizedText, "Calculating time left")
        XCTAssertEqual(TimeRemaining.fullyCharged.localizedText, "Fully charged")
        XCTAssertEqual(TimeRemaining.runningFromAdapter.localizedText, "Running from adapter")
        XCTAssertEqual(TimeRemaining.adapterCannotKeepUp(ratedWatts: 20).localizedText, "The 20 W adapter can't keep up")
        XCTAssertEqual(TimeRemaining.adapterCannotKeepUp(ratedWatts: nil).localizedText, "The adapter can't keep up")
        XCTAssertEqual(TimeRemaining.usingBatteryOnAdapter.localizedText, "Using the battery while plugged in")
        XCTAssertEqual(TimeRemaining.waitingForFirstReading.localizedText, "Waiting for first reading")
    }

    func testTimeRemainingTextsFollowTheCoreEnglishText() {
        let cases: [TimeRemaining] = [
            .untilFull(minutes: 75), .finishingCharge, .calculatingUntilFull, .fullyCharged,
            .runningFromAdapter, .adapterCannotKeepUp(ratedWatts: 20), .adapterCannotKeepUp(ratedWatts: nil), .usingBatteryOnAdapter,
            .untilEmpty(minutes: 192), .calculatingUntilEmpty, .waitingForFirstReading
        ]
        for remaining in cases {
            XCTAssertEqual(remaining.localizedText, remaining.text)
        }
    }

    func testActionResultMessagesComeFromTheReason() {
        func message(_ reason: ServiceActionReason) -> String {
            ServiceActionResult(reason: reason).localizedMessage
        }

        XCTAssertEqual(message(.applied(.lowPower)), "Low Power applied")
        XCTAssertEqual(message(.systemKeptMode(.automatic)), "System kept Automatic")
        XCTAssertEqual(message(.canceled), "Authorization canceled")
        XCTAssertEqual(message(.timedOut), "Authorization timed out")
        XCTAssertEqual(message(.failed(detail: nil)), "Power mode update failed")
    }

    func testFailureDetailIsShownAsReportedBySystem() {
        let result = ServiceActionResult(reason: .failed(detail: "execution error: not authorized (-60007)"))

        XCTAssertEqual(result.localizedMessage, "execution error: not authorized (-60007)")
    }

    func testActionResultMessagesFollowTheCoreEnglishMessage() {
        let reasons: [ServiceActionReason] = [
            .applied(.highPower), .systemKeptMode(.lowPower), .canceled, .timedOut, .failed(detail: nil), .failed(detail: "boom")
        ]
        for reason in reasons {
            let result = ServiceActionResult(reason: reason)
            XCTAssertEqual(result.localizedMessage, result.message)
        }
    }

    func testWarningsFollowTheCoreEnglishMessage() {
        for warning in SnapshotWarning.allCases {
            XCTAssertEqual(warning.localizedMessage, warning.message)
            XCTAssertEqual(SnapshotWarning.localizedMessage(for: warning.message), warning.localizedMessage)
        }
    }

    func testUnknownWarningsAreShownAsTheyCame() {
        XCTAssertEqual(SnapshotWarning.localizedMessage(for: "something else failed"), "something else failed")
    }

    func testKnownBatteryConditionsAreTranslatedAndOthersPassThrough() {
        XCTAssertEqual(BatteryCondition.localizedText("Normal"), "Normal")
        XCTAssertEqual(BatteryCondition.localizedText("Service Recommended"), "Service Recommended")
        XCTAssertEqual(BatteryCondition.localizedText("Replace Soon"), "Replace Soon")
    }

    func testNotificationTitles() {
        XCTAssertEqual(BatteryAlert(kind: .lowBattery, level: 20).title, "Battery low")
        XCTAssertEqual(BatteryAlert(kind: .chargeLimit, level: 80).title, "Charge limit reached")
        XCTAssertEqual(BatteryAlert(kind: .fullyCharged, level: 100).title, "Battery fully charged")
    }

    func testNotificationMessagesMentionTheLevelWhereItMatters() {
        XCTAssertEqual(
            BatteryAlert(kind: .lowBattery, level: 20).message,
            "The battery is at \(ValueFormat.percent(20)). Plug in your charger."
        )
        XCTAssertEqual(
            BatteryAlert(kind: .chargeLimit, level: 80).message,
            "The battery reached \(ValueFormat.percent(80)). Unplug to go easy on its health."
        )
        XCTAssertEqual(
            BatteryAlert(kind: .fullyCharged, level: 100).message,
            "The battery is full. You can unplug your charger."
        )
    }

    func testLastRefreshNamesTheTriggerAndTheDuration() {
        let expected: [(RefreshTrigger, String)] = [
            (.launch, "Last refresh: launch · 12 ms"),
            (.timer, "Last refresh: timer · 12 ms"),
            (.surface, "Last refresh: opened · 12 ms"),
            (.powerEvent, "Last refresh: power event · 12 ms"),
            (.manual, "Last refresh: manual · 12 ms"),
            (.modeChange, "Last refresh: mode change · 12 ms"),
            (.queued, "Last refresh: queued · 12 ms")
        ]
        for (trigger, text) in expected {
            XCTAssertEqual(trigger.localizedLastRefresh(milliseconds: 12), text)
        }
    }
}
