import Foundation

enum PowerReadingSanitizer {
    // Right after unplugging, the registry briefly keeps the charging sign on the battery readings and reports a negative load.
    static func batteryFlow(_ value: Double?, onExternalPower: Bool) -> Double? {
        guard let value else { return nil }
        return onExternalPower || value <= 0 ? value : -value
    }

    static func systemLoad(_ watts: Double?) -> Double? {
        guard let watts, watts >= 0 else { return nil }
        return watts
    }
}
