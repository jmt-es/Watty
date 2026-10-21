import Foundation
import WattyCore

extension ServiceActionResult {
    var localizedMessage: String {
        switch reason {
        case .applied(let mode):
            return String(localized: "\(mode.localizedLongTitle) applied")
        case .systemKeptMode(let mode):
            return String(localized: "System kept \(mode.localizedLongTitle)")
        case .canceled:
            return String(localized: "Authorization canceled")
        case .timedOut:
            return String(localized: "Authorization timed out")
        case .failed(let detail):
            return detail ?? String(localized: "Power mode update failed")
        }
    }
}
