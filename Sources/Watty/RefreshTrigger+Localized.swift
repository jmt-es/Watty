import Foundation

extension RefreshTrigger {
    func localizedLastRefresh(milliseconds: Int) -> String {
        switch self {
        case .launch: return String(localized: "Last refresh: launch · \(milliseconds) ms")
        case .timer: return String(localized: "Last refresh: timer · \(milliseconds) ms")
        case .surface: return String(localized: "Last refresh: opened · \(milliseconds) ms")
        case .powerEvent: return String(localized: "Last refresh: power event · \(milliseconds) ms")
        case .manual: return String(localized: "Last refresh: manual · \(milliseconds) ms")
        case .modeChange: return String(localized: "Last refresh: mode change · \(milliseconds) ms")
        case .queued: return String(localized: "Last refresh: queued · \(milliseconds) ms")
        }
    }
}
