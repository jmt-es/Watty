import Foundation

enum BatteryCondition {
    static func localizedText(_ condition: String) -> String {
        switch condition {
        case "Normal": return String(localized: "Normal")
        case "Service Recommended": return String(localized: "Service Recommended")
        default: return condition
        }
    }
}
