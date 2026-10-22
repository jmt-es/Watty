import SwiftUI
import XCTest
@testable import Watty
import WattyCore

final class ChargeStatusStyleTests: XCTestCase {
    private let allStates: [ChargeState] = [.charging, .charged, .pluggedInNotCharging, .pluggedInDraining, .onBattery, .unknown]

    private func style(_ state: ChargeState, level: Int = 50) -> ChargeStatusStyle {
        ChargeStatusStyle(chargeState: state, level: level)
    }

    func testPluggedInAndDrainingIsAnOrangeWarningOnTheHeaderAndTheRing() {
        let draining = style(.pluggedInDraining, level: 18)

        XCTAssertEqual(draining.symbol, ChargeSymbol.draining)
        XCTAssertEqual(draining.ringSymbol, ChargeSymbol.draining)
        XCTAssertEqual(draining.tint, .orange)
        XCTAssertEqual(draining.textColor, .orange)
        XCTAssertEqual(draining.subtitleColor, .orange)
    }

    func testPluggedInAndDrainingNeverShowsTheGreenBolt() {
        let draining = style(.pluggedInDraining)

        XCTAssertNotEqual(draining.symbol, ChargeSymbol.charging)
        XCTAssertNotEqual(draining.ringSymbol, ChargeSymbol.charging)
        XCTAssertNotEqual(draining.tint, .green)
        XCTAssertNotEqual(draining.textColor, .green)
    }

    func testChargingKeepsItsGreenBolt() {
        let charging = style(.charging)

        XCTAssertEqual(charging.symbol, ChargeSymbol.charging)
        XCTAssertEqual(charging.ringSymbol, ChargeSymbol.charging)
        XCTAssertEqual(charging.tint, .green)
        XCTAssertEqual(charging.textColor, .green)
    }

    func testOnlyChargingAndDrainingPutAGlyphInTheRing() {
        for state in allStates {
            let hasGlyph = style(state).ringSymbol != nil

            XCTAssertEqual(hasGlyph, state == .charging || state == .pluggedInDraining, "\(state)")
        }
    }

    func testEveryStateHasItsOwnHeaderSymbol() {
        XCTAssertEqual(Set(allStates.map { style($0).symbol }).count, allStates.count)
    }

    func testOnBatteryTurnsOrangeOnlyAtTheLowLevel() {
        XCTAssertEqual(style(.onBattery, level: BatteryThreshold.lowLevel).tint, .orange)
        XCTAssertEqual(style(.onBattery, level: BatteryThreshold.lowLevel).textColor, .orange)
        XCTAssertEqual(style(.onBattery, level: BatteryThreshold.lowLevel + 1).tint, .teal)
        XCTAssertEqual(style(.onBattery, level: BatteryThreshold.lowLevel + 1).textColor, .primary)
    }

    func testOnlyTheDrainColorsTheHeaderSubtitle() {
        for state in allStates where state != .pluggedInDraining {
            XCTAssertEqual(style(state).subtitleColor, .secondary, "\(state)")
        }
    }

    func testThePluggedInStatesKeepTheirColors() {
        XCTAssertEqual(style(.charged).tint, .green)
        XCTAssertEqual(style(.pluggedInNotCharging).tint, .yellow)
        XCTAssertEqual(style(.unknown).tint, .secondary)
    }
}
