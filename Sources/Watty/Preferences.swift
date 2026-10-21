import Foundation

enum PreferenceKey {
    static let menuBarDisplay = "menuBarDisplay"
    static let batteryChartRange = "batteryChartRangeHours"
    static let healthExpanded = "healthExpanded"
    static let notifyLowBattery = "notifyLowBattery"
    static let lowBatteryLevel = "lowBatteryLevel"
    static let notifyChargeLimit = "notifyChargeLimit"
    static let chargeLimitLevel = "chargeLimitLevel"
    static let notifyFullyCharged = "notifyFullyCharged"
}

enum PreferenceDefault {
    static let lowBatteryLevel = 20
    static let lowBatteryLevels = 5...50
    static let chargeLimitLevel = 80
    static let chargeLimitLevels = 50...100
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case percentage
    case timeRemaining
    case power
    case iconOnly

    var id: String { rawValue }

    static func options(hasBattery: Bool) -> [MenuBarDisplay] {
        hasBattery ? allCases : [.percentage, .iconOnly]
    }
}

protocol PreferenceSource {
    func object(forKey defaultName: String) -> Any?
    func bool(forKey defaultName: String) -> Bool
    func string(forKey defaultName: String) -> String?
}

extension UserDefaults: PreferenceSource {}

enum Preferences {
    static func menuBarDisplay(from defaults: PreferenceSource = UserDefaults.standard) -> MenuBarDisplay {
        defaults.string(forKey: PreferenceKey.menuBarDisplay).flatMap(MenuBarDisplay.init(rawValue:)) ?? .percentage
    }

    static func alertConfiguration(from defaults: PreferenceSource = UserDefaults.standard) -> BatteryAlertConfiguration {
        BatteryAlertConfiguration(
            lowBatteryEnabled: defaults.bool(forKey: PreferenceKey.notifyLowBattery),
            lowBatteryLevel: level(
                forKey: PreferenceKey.lowBatteryLevel,
                default: PreferenceDefault.lowBatteryLevel,
                range: PreferenceDefault.lowBatteryLevels,
                in: defaults
            ),
            chargeLimitEnabled: defaults.bool(forKey: PreferenceKey.notifyChargeLimit),
            chargeLimitLevel: level(
                forKey: PreferenceKey.chargeLimitLevel,
                default: PreferenceDefault.chargeLimitLevel,
                range: PreferenceDefault.chargeLimitLevels,
                in: defaults
            ),
            fullyChargedEnabled: defaults.bool(forKey: PreferenceKey.notifyFullyCharged)
        )
    }

    private static func level(forKey key: String, default fallback: Int, range: ClosedRange<Int>, in defaults: PreferenceSource) -> Int {
        let stored = defaults.object(forKey: key) as? Int ?? fallback
        return min(max(stored, range.lowerBound), range.upperBound)
    }
}
