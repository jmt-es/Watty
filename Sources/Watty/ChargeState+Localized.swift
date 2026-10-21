import Foundation
import WattyCore

extension ChargeState {
    var localizedTitle: String {
        switch self {
        case .charging: return String(localized: "Charging")
        case .charged: return String(localized: "Charged")
        case .pluggedInNotCharging: return String(localized: "Plugged in, not charging")
        case .onBattery: return String(localized: "On battery")
        case .unknown: return String(localized: "Reading battery")
        }
    }
}
