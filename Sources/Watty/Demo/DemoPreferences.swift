import Foundation

enum DemoPreferences {
    static let values: [String: Any] = [
        PreferenceKey.menuBarDisplay: MenuBarDisplay.percentage.rawValue,
        PreferenceKey.batteryChartRange: BatteryChartRange.sixHours.rawValue,
        PreferenceKey.healthExpanded: false,
        PreferenceKey.notifyLowBattery: true,
        PreferenceKey.lowBatteryLevel: PreferenceDefault.lowBatteryLevel,
        PreferenceKey.notifyChargeLimit: true,
        PreferenceKey.chargeLimitLevel: PreferenceDefault.chargeLimitLevel,
        PreferenceKey.notifyFullyCharged: false
    ]

    static func merged(into arguments: [String: Any]) -> [String: Any] {
        values.merging(arguments) { _, explicit in explicit }
    }

    // The argument domain outranks stored preferences and is never written to disk.
    static func apply(to defaults: UserDefaults = .standard) {
        let arguments = merged(into: defaults.volatileDomain(forName: UserDefaults.argumentDomain))
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
