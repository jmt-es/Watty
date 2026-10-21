import Foundation
import WattyCore

extension PowerMode {
    var localizedTitle: String {
        switch self {
        case .automatic: return String(localized: "Auto")
        case .lowPower: return String(localized: "Low")
        case .highPower: return String(localized: "High")
        }
    }

    var localizedLongTitle: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .lowPower: return String(localized: "Low Power")
        case .highPower: return String(localized: "High Power")
        }
    }
}
