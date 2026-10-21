import XCTest
@testable import Watty

final class PreferencesTests: XCTestCase {
    private struct StubPreferences: PreferenceSource {
        var values: [String: Any] = [:]

        func object(forKey defaultName: String) -> Any? { values[defaultName] }
        func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
        func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    }

    func testAlertDefaultsMatchTheDocumentedOnes() {
        let configuration = Preferences.alertConfiguration(from: StubPreferences())

        XCTAssertEqual(configuration.lowBatteryLevel, 20)
        XCTAssertEqual(configuration.chargeLimitLevel, 80)
        XCTAssertFalse(configuration.lowBatteryEnabled)
        XCTAssertFalse(configuration.chargeLimitEnabled)
        XCTAssertFalse(configuration.fullyChargedEnabled)
    }

    func testStoredLevelsAreClampedToTheirRanges() {
        let tooLow = StubPreferences(values: [PreferenceKey.lowBatteryLevel: 1, PreferenceKey.chargeLimitLevel: 10])
        let tooHigh = StubPreferences(values: [PreferenceKey.lowBatteryLevel: 90, PreferenceKey.chargeLimitLevel: 500])

        XCTAssertEqual(Preferences.alertConfiguration(from: tooLow).lowBatteryLevel, 5)
        XCTAssertEqual(Preferences.alertConfiguration(from: tooLow).chargeLimitLevel, 50)
        XCTAssertEqual(Preferences.alertConfiguration(from: tooHigh).lowBatteryLevel, 50)
        XCTAssertEqual(Preferences.alertConfiguration(from: tooHigh).chargeLimitLevel, 100)
    }

    func testTogglesAreReadFromTheirKeys() {
        let preferences = StubPreferences(values: [
            PreferenceKey.notifyLowBattery: true,
            PreferenceKey.notifyFullyCharged: true
        ])

        let configuration = Preferences.alertConfiguration(from: preferences)

        XCTAssertTrue(configuration.lowBatteryEnabled)
        XCTAssertFalse(configuration.chargeLimitEnabled)
        XCTAssertTrue(configuration.fullyChargedEnabled)
    }

    func testMenuBarDisplayFallsBackToPercentage() {
        XCTAssertEqual(Preferences.menuBarDisplay(from: StubPreferences()), .percentage)
        XCTAssertEqual(Preferences.menuBarDisplay(from: StubPreferences(values: [PreferenceKey.menuBarDisplay: "bogus"])), .percentage)
        XCTAssertEqual(Preferences.menuBarDisplay(from: StubPreferences(values: [PreferenceKey.menuBarDisplay: "power"])), .power)
        XCTAssertEqual(Preferences.menuBarDisplay(from: StubPreferences(values: [PreferenceKey.menuBarDisplay: "timeRemaining"])), .timeRemaining)
    }
}
