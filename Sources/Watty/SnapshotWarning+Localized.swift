import Foundation
import WattyCore

extension SnapshotWarning {
    var localizedMessage: String {
        switch self {
        case .powerSourceReadFailed: return String(localized: "IOKit power source read failed")
        case .smartBatteryReadFailed: return String(localized: "AppleSmartBattery read failed")
        case .ioregBatteryReadFailed: return String(localized: "ioreg battery read failed")
        case .pmsetBatteryReadFailed: return String(localized: "pmset battery read failed")
        case .pmsetSettingsReadFailed: return String(localized: "pmset settings read failed")
        case .systemProfilerDetailReadFailed: return String(localized: "system_profiler detail read failed")
        }
    }

    static func localizedMessage(for warning: String) -> String {
        SnapshotWarning(rawValue: warning)?.localizedMessage ?? warning
    }
}
