import Foundation
import WattyCore

enum TextFormat {
    static let missing = "—"
    static let separator = " · "

    private static let idleBatteryWatts = 0.4
    private static let oneDecimalHalfStep = 0.05
    private static let twoDecimalHalfStep = 0.005
    private static let byteUnits = ["B", "KB", "MB", "GB", "TB"]
    private static let bytesPerUnit = 1024.0

    static func number(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f", value)
    }

    static func signedNumber(_ value: Double?) -> String {
        guard let value else { return missing }
        if abs(value) < oneDecimalHalfStep { return "0.0" }
        return String(format: "%+.1f", value)
    }

    static func watts(_ value: Double?) -> String {
        value == nil ? missing : number(value) + " W"
    }

    static func signedWatts(_ value: Double?) -> String {
        value == nil ? missing : signedNumber(value) + " W"
    }

    static func volts(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.2f V", value)
    }

    static func signedAmps(_ value: Double?) -> String {
        guard let value else { return missing }
        if abs(value) < twoDecimalHalfStep { return "0.00 A" }
        return String(format: "%+.2f A", value)
    }

    static func celsius(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f °C", value)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f%%", value)
    }

    static func percent(_ value: Int?) -> String {
        guard let value else { return missing }
        return "\(value)%"
    }

    static func integer(_ value: Int?) -> String {
        value.map(String.init) ?? missing
    }

    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return missing }
        var amount = Double(value)
        var unitIndex = 0
        while amount >= bytesPerUnit, unitIndex < byteUnits.count - 1 {
            amount /= bytesPerUnit
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(value) B" }
        return String(format: "%.\(decimalsForThreeSignificantDigits(amount))f", amount) + " " + byteUnits[unitIndex]
    }

    private static func decimalsForThreeSignificantDigits(_ amount: Double) -> Int {
        if amount < 10 { return 2 }
        if amount < 100 { return 1 }
        return 0
    }

    static func seconds(_ value: TimeInterval) -> String {
        String(format: "%g s", value)
    }

    static func batteryFlow(_ watts: Double?) -> String? {
        guard let watts else { return nil }
        if watts > idleBatteryWatts { return "charging" }
        if watts < -idleBatteryWatts { return "discharging" }
        return "idle"
    }

    static func clock(minutes: Int) -> String {
        BatterySnapshot.clockText(minutes: minutes)
    }
}
