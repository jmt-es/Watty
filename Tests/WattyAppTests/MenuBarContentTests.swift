import XCTest
@testable import Watty
import WattyCore

final class MenuBarContentTests: XCTestCase {
    private func snapshot(
        level: Int = 82,
        charging: Bool = false,
        adapter: Bool = false,
        full: Bool = false,
        flow: NetFlow? = nil
    ) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = Date()
        snapshot.level = level
        snapshot.isCharging = charging
        snapshot.isFullyCharged = full
        snapshot.powerSource = adapter ? .adapter : .battery
        snapshot.netFlow = NetFlowEstimate(flow: flow)
        return snapshot
    }

    func testPercentageDisplay() {
        let content = MenuBarContent(snapshot: snapshot(), cpuPercent: 12, display: .percentage)
        let percent = ValueFormat.percent(82)
        XCTAssertEqual(content.text, percent)
        XCTAssertEqual(content.symbolName, "battery.75")
        XCTAssertEqual(content.accessibilityLabel, String(localized: "Battery \(percent), on battery"))
    }

    func testChargingAccessibilityLabelMentionsCharging() {
        let content = MenuBarContent(snapshot: snapshot(charging: true, adapter: true), cpuPercent: nil, display: .percentage)
        XCTAssertEqual(content.symbolName, "battery.100.bolt")
        XCTAssertEqual(content.accessibilityLabel, String(localized: "Battery \(ValueFormat.percent(82)), charging"))
    }

    func testPluggedInAndDrainingHasItsOwnSymbolAndSpokenLabel() {
        let draining = snapshot(level: 18, charging: true, adapter: true, flow: .draining)

        let content = MenuBarContent(snapshot: draining, cpuPercent: nil, display: .percentage)

        XCTAssertEqual(content.symbolName, ChargeSymbol.draining)
        XCTAssertNotEqual(content.symbolName, "battery.100.bolt")
        XCTAssertEqual(content.text, ValueFormat.percent(18))
        XCTAssertEqual(content.accessibilityLabel, String(localized: "Battery \(ValueFormat.percent(18)), plugged in, draining"))
    }

    func testTheSymbolOfAChargerThatKeepsUpIsStillTheChargingOne() {
        for flow in [nil, NetFlow.charging, .holding] {
            let content = MenuBarContent(snapshot: snapshot(charging: true, adapter: true, flow: flow), cpuPercent: nil, display: .percentage)

            XCTAssertEqual(content.symbolName, "battery.100.bolt", "\(String(describing: flow))")
        }
    }

    func testOnBatteryTheDrainDoesNotChangeTheSymbol() {
        let content = MenuBarContent(snapshot: snapshot(level: 18, flow: .draining), cpuPercent: nil, display: .percentage)

        XCTAssertEqual(content.symbolName, "battery.25")
        XCTAssertEqual(content.accessibilityLabel, String(localized: "Battery \(ValueFormat.percent(18)), on battery"))
    }

    func testWhilePluggedInAndDrainingTheTimeDisplayFallsBackToThePercentage() {
        var draining = snapshot(level: 18, charging: true, adapter: true, flow: .draining)
        draining.timeToFullMinutes = 579

        let content = MenuBarContent(snapshot: draining, cpuPercent: nil, display: .timeRemaining)

        XCTAssertEqual(content.text, ValueFormat.percent(18))
        XCTAssertNil(content.accessibilityValue)
    }

    func testWhilePluggedInAndDrainingThePowerDisplayStillShowsTheAdapterInput() {
        var draining = snapshot(level: 18, charging: true, adapter: true, flow: .draining)
        draining.systemPowerWatts = 19.7

        let content = MenuBarContent(snapshot: draining, cpuPercent: nil, display: .power)

        XCTAssertEqual(content.text, ValueFormat.watts(19.7))
    }

    func testBeforeTheFirstReadingShowsPlaceholderNotZero() {
        let content = MenuBarContent(snapshot: .empty, cpuPercent: nil, display: .percentage)
        XCTAssertEqual(content.text, "--")
        XCTAssertFalse(content.text?.contains("0") ?? false)
    }

    func testIconOnlyHasNoText() {
        XCTAssertNil(MenuBarContent(snapshot: snapshot(), cpuPercent: nil, display: .iconOnly).text)
    }

    func testTimeRemainingOnBatteryAndCharging() {
        var onBattery = snapshot()
        onBattery.timeToEmptyMinutes = 192
        XCTAssertEqual(MenuBarContent(snapshot: onBattery, cpuPercent: nil, display: .timeRemaining).text, "3:12")

        var charging = snapshot(charging: true, adapter: true)
        charging.timeToFullMinutes = 45
        XCTAssertEqual(MenuBarContent(snapshot: charging, cpuPercent: nil, display: .timeRemaining).text, "0:45")
    }

    func testTimeRemainingShowsPendingClockWhileEstimating() {
        let content = MenuBarContent(snapshot: snapshot(), cpuPercent: nil, display: .timeRemaining)
        XCTAssertEqual(content.text, "--:--")
        XCTAssertNil(content.accessibilityValue)
    }

    func testTimeRemainingFallsBackToPercentageWhenPluggedInAndFull() {
        let content = MenuBarContent(snapshot: snapshot(level: 100, adapter: true, full: true), cpuPercent: nil, display: .timeRemaining)
        XCTAssertEqual(content.text, ValueFormat.percent(100))
    }

    func testPowerDisplayUsesDischargeWattsOnBatteryAndAdapterInputWhenPlugged() {
        var onBattery = snapshot()
        onBattery.batteryPowerWatts = -8.4
        XCTAssertEqual(MenuBarContent(snapshot: onBattery, cpuPercent: nil, display: .power).text, ValueFormat.watts(8.4))

        var glitchy = snapshot()
        glitchy.batteryPowerWatts = 21.9
        XCTAssertEqual(MenuBarContent(snapshot: glitchy, cpuPercent: nil, display: .power).text, ValueFormat.watts(21.9))

        var plugged = snapshot(charging: true, adapter: true)
        plugged.systemPowerWatts = 45.2
        plugged.batteryPowerWatts = 20
        let content = MenuBarContent(snapshot: plugged, cpuPercent: nil, display: .power)
        XCTAssertEqual(content.text, ValueFormat.watts(45.2))
        XCTAssertEqual(content.accessibilityValue, ValueFormat.spokenWatts(45.2))
    }

    func testPowerDisplayWithoutReadingShowsMissing() {
        XCTAssertEqual(MenuBarContent(snapshot: snapshot(), cpuPercent: nil, display: .power).text, ValueFormat.missing)
    }

    func testMacWithoutBatteryShowsCpuAndNeverZeroPercent() {
        var desktop = snapshot(level: 0)
        desktop.hasBattery = false
        let content = MenuBarContent(snapshot: desktop, cpuPercent: 37.4, display: .percentage)
        XCTAssertEqual(content.symbolName, "cpu")
        XCTAssertEqual(content.text, ValueFormat.percent(37.4))
        XCTAssertEqual(content.accessibilityLabel, String(localized: "CPU usage \(ValueFormat.percent(37.4))"))

        let pending = MenuBarContent(snapshot: desktop, cpuPercent: nil, display: .power)
        XCTAssertEqual(pending.text, "--")
        XCTAssertNil(MenuBarContent(snapshot: desktop, cpuPercent: 10, display: .iconOnly).text)
    }

    func testMenuBarOptionsDependOnBattery() {
        XCTAssertEqual(MenuBarDisplay.options(hasBattery: true), MenuBarDisplay.allCases)
        XCTAssertEqual(MenuBarDisplay.options(hasBattery: false), [.percentage, .iconOnly])
    }
}
