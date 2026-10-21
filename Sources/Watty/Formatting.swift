import Foundation

enum ValueFormat {
    static let missing = "---"

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    static func decimal(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(localized: "\(decimal(value, fractionDigits: 1)) W")
    }

    static func signedWatts(_ value: Double?) -> String {
        guard let value else { return missing }
        if abs(value) < 0.05 { return String(localized: "\(decimal(0, fractionDigits: 1)) W") }
        let signed = value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return String(localized: "\(signed) W")
    }

    static func volts(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(localized: "\(decimal(value, fractionDigits: 2)) V")
    }

    static func amps(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(localized: "\(decimal(value, fractionDigits: 2)) A")
    }

    static func celsius(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(localized: "\(decimal(value, fractionDigits: 1)) °C")
    }

    static func wholeCelsius(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(localized: "\(decimal(value.rounded(), fractionDigits: 0)) °C")
    }

    static func integer(_ value: Int?) -> String {
        value.map { $0.formatted() } ?? missing
    }

    static func percent(_ value: Int?) -> String {
        value.map { percentText(Double($0), fractionDigits: 0) } ?? missing
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return missing }
        return percentText(value.rounded(), fractionDigits: 0)
    }

    static func cpuPercent(_ value: Double) -> String {
        percentText(value, fractionDigits: value < 10 ? 1 : 0)
    }

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date).rounded()))
        if seconds < 2 { return String(localized: "just now") }
        if seconds < 60 { return String(localized: "\(seconds) s ago") }
        let minutes = seconds / 60
        if minutes < 60 { return String(localized: "\(minutes) min ago") }
        return String(localized: "\(minutes / 60) h \(minutes % 60) min ago")
    }

    static func spokenWatts(_ value: Double) -> String {
        String(localized: "\(decimal(value, fractionDigits: 1)) watts")
    }

    private static func percentText(_ value: Double, fractionDigits: Int) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(fractionDigits)))
    }
}
