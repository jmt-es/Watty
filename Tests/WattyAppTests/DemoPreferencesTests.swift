import XCTest
@testable import Watty

final class DemoPreferencesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ArgumentDomainSandbox.install(in: self)
    }

    func testDemoValuesFillWhatTheCommandLineLeavesOut() {
        let merged = DemoPreferences.merged(into: ["-AppleLocale": "en_US"])

        XCTAssertEqual(merged["-AppleLocale"] as? String, "en_US")
        XCTAssertEqual(merged[PreferenceKey.healthExpanded] as? Bool, false)
        XCTAssertEqual(merged[PreferenceKey.menuBarDisplay] as? String, MenuBarDisplay.percentage.rawValue)
        XCTAssertEqual(merged[PreferenceKey.batteryChartRange] as? Int, BatteryChartRange.sixHours.rawValue)
        XCTAssertEqual(merged.count, DemoPreferences.values.count + 1)
    }

    func testValuesGivenOnTheCommandLineWinOverTheDemoOnes() {
        let merged = DemoPreferences.merged(into: [PreferenceKey.healthExpanded: true])

        XCTAssertEqual(merged[PreferenceKey.healthExpanded] as? Bool, true)
        XCTAssertEqual(merged[PreferenceKey.notifyLowBattery] as? Bool, true)
    }

    func testEveryDemoValueMatchesTheTypeItsPreferenceIsStoredWith() {
        let values = DemoPreferences.values

        XCTAssertNotNil(values[PreferenceKey.menuBarDisplay] as? String)
        XCTAssertNotNil(values[PreferenceKey.batteryChartRange] as? Int)
        for key in [PreferenceKey.healthExpanded, PreferenceKey.notifyLowBattery, PreferenceKey.notifyChargeLimit, PreferenceKey.notifyFullyCharged] {
            XCTAssertNotNil(values[key] as? Bool, key)
        }
        for key in [PreferenceKey.lowBatteryLevel, PreferenceKey.chargeLimitLevel] {
            XCTAssertNotNil(values[key] as? Int, key)
        }
        XCTAssertEqual(values.count, 8)
    }

    func testApplyingMakesThePreferencesVisibleToTheViewsAndOnlyForThisProcess() {
        let defaults = UserDefaults.standard
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain([PreferenceKey.chargeLimitLevel: 90], forName: UserDefaults.argumentDomain)

        DemoPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.object(forKey: PreferenceKey.healthExpanded) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: PreferenceKey.notifyLowBattery) as? Bool, true)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.chargeLimitLevel), 90)
        XCTAssertNil(defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[PreferenceKey.notifyLowBattery])
    }

    func testApplyingTwiceKeepsTheSameValues() {
        let defaults = UserDefaults.standard

        DemoPreferences.apply(to: defaults)
        DemoPreferences.apply(to: defaults)

        XCTAssertEqual(defaults.object(forKey: PreferenceKey.notifyLowBattery) as? Bool, true)
        XCTAssertEqual(defaults.integer(forKey: PreferenceKey.lowBatteryLevel), PreferenceDefault.lowBatteryLevel)
    }
}
