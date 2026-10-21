import XCTest
@testable import Watty
import WattyCore

final class BatteryAlertEvaluatorTests: XCTestCase {
    private let allOn = BatteryAlertConfiguration(
        lowBatteryEnabled: true, lowBatteryLevel: 20,
        chargeLimitEnabled: true, chargeLimitLevel: 80,
        fullyChargedEnabled: true
    )

    private func kinds(_ alerts: [BatteryAlert]) -> [BatteryAlertKind] { alerts.map(\.kind) }

    func testLowBatteryFiresOnceWhenCrossingTheThreshold() {
        var evaluator = BatteryAlertEvaluator()
        XCTAssertEqual(kinds(evaluator.evaluate(level: 30, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 21, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 20, chargeState: .onBattery, configuration: allOn)), [.lowBattery])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 19, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 5, chargeState: .onBattery, configuration: allOn)), [])
    }

    func testAlreadyBelowThresholdAtFirstObservationStaysSilent() {
        var evaluator = BatteryAlertEvaluator()
        XCTAssertEqual(kinds(evaluator.evaluate(level: 12, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 11, chargeState: .onBattery, configuration: allOn)), [])
    }

    func testLowBatteryNeedsAMarginBeforeItRearms() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 25, chargeState: .onBattery, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 20, chargeState: .onBattery, configuration: allOn)), [.lowBattery])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 21, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 20, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 22, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 20, chargeState: .onBattery, configuration: allOn)), [.lowBattery])
    }

    func testLowBatteryRearmsWhenTheChargerIsConnected() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 25, chargeState: .onBattery, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 18, chargeState: .onBattery, configuration: allOn)), [.lowBattery])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 18, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 17, chargeState: .onBattery, configuration: allOn)), [.lowBattery])
    }

    func testLowBatteryIgnoresChargingBelowTheThreshold() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 40, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 10, chargeState: .charging, configuration: allOn)), [])
    }

    func testChargeLimitFiresWhenChargingReachesTheLevelAndNotAgainWhileCharging() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 70, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 79, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 81, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 99, chargeState: .charging, configuration: allOn)), [])
    }

    func testChargeLimitStaysQuietWhenMacOSHoldsTheChargeAtTheLimit() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 75, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .pluggedInNotCharging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 79, chargeState: .pluggedInNotCharging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [])
    }

    func testChargeLimitRearmsAfterUnplugging() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 75, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .onBattery, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 85, chargeState: .charging, configuration: allOn)), [.chargeLimit])
    }

    func testChargeLimitRearmsAfterTheLevelDropsEnough() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 75, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 79, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 78, chargeState: .charging, configuration: allOn)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
    }

    func testChargeLimitAtOneHundredFiresWhenTheBatteryIsFull() {
        var evaluator = BatteryAlertEvaluator()
        let config = BatteryAlertConfiguration(lowBatteryEnabled: false, lowBatteryLevel: 20, chargeLimitEnabled: true, chargeLimitLevel: 100, fullyChargedEnabled: false)
        _ = evaluator.evaluate(level: 98, chargeState: .charging, configuration: config)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [.chargeLimit])
    }

    func testFullyChargedFiresOnceAndIgnoresTopUps() {
        var evaluator = BatteryAlertEvaluator()
        let config = BatteryAlertConfiguration(lowBatteryEnabled: false, lowBatteryLevel: 20, chargeLimitEnabled: false, chargeLimitLevel: 80, fullyChargedEnabled: true)
        _ = evaluator.evaluate(level: 90, chargeState: .charging, configuration: config)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [.fullyCharged])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 99, chargeState: .charging, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 97, chargeState: .charging, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [])
    }

    func testChargeLimitAndFullyChargedBothFireWhenTheyAreArmed() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 70, chargeState: .charging, configuration: allOn)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 80, chargeState: .charging, configuration: allOn)), [.chargeLimit])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: allOn)), [.fullyCharged])
    }

    func testFullyChargedRearmsAfterUnplugging() {
        var evaluator = BatteryAlertEvaluator()
        let config = BatteryAlertConfiguration(lowBatteryEnabled: false, lowBatteryLevel: 20, chargeLimitEnabled: false, chargeLimitLevel: 80, fullyChargedEnabled: true)
        _ = evaluator.evaluate(level: 95, chargeState: .charging, configuration: config)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [.fullyCharged])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 99, chargeState: .onBattery, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 100, chargeState: .charged, configuration: config)), [.fullyCharged])
    }

    func testFullyChargedNeverLoopsWhenTheChargedFlagIsReportedBelowTheRearmLevel() {
        var evaluator = BatteryAlertEvaluator()
        let config = BatteryAlertConfiguration(lowBatteryEnabled: false, lowBatteryLevel: 20, chargeLimitEnabled: false, chargeLimitLevel: 80, fullyChargedEnabled: true)
        _ = evaluator.evaluate(level: 85, chargeState: .charging, configuration: config)
        var fired = 0
        for _ in 0..<10 {
            fired += evaluator.evaluate(level: 90, chargeState: .charged, configuration: config).count
        }
        XCTAssertEqual(fired, 1)
    }

    func testDisabledAlertsNeverFireAndReenablingStartsSilently() {
        var evaluator = BatteryAlertEvaluator()
        var config = allOn
        config.lowBatteryEnabled = false
        _ = evaluator.evaluate(level: 30, chargeState: .onBattery, configuration: config)
        XCTAssertEqual(kinds(evaluator.evaluate(level: 15, chargeState: .onBattery, configuration: config)), [])
        config.lowBatteryEnabled = true
        XCTAssertEqual(kinds(evaluator.evaluate(level: 15, chargeState: .onBattery, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 14, chargeState: .onBattery, configuration: config)), [])
    }

    func testChangingTheThresholdRestartsTrackingWithoutFiring() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 40, chargeState: .onBattery, configuration: allOn)
        var config = allOn
        config.lowBatteryLevel = 50
        XCTAssertEqual(kinds(evaluator.evaluate(level: 40, chargeState: .onBattery, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 39, chargeState: .onBattery, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 60, chargeState: .charging, configuration: config)), [])
        XCTAssertEqual(kinds(evaluator.evaluate(level: 50, chargeState: .onBattery, configuration: config)), [.lowBattery])
    }

    func testAlertCarriesTheLevel() {
        var evaluator = BatteryAlertEvaluator()
        _ = evaluator.evaluate(level: 30, chargeState: .onBattery, configuration: allOn)
        let alerts = evaluator.evaluate(level: 19, chargeState: .onBattery, configuration: allOn)
        XCTAssertEqual(alerts, [BatteryAlert(kind: .lowBattery, level: 19)])
    }
}
