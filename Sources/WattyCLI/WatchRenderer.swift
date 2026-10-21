import Foundation
import WattyCore

enum WatchRenderer {
    private static let noBatteryState = "no_battery"

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func frame(report: StatusReport, interval: TimeInterval, date: Date, style: TextStyle) -> [String] {
        let details = [
            report.wattyVersion,
            "every \(TextFormat.seconds(interval))",
            clockFormatter.string(from: date),
            "Ctrl-C to quit"
        ].joined(separator: TextFormat.separator)
        var lines = [style.bold("Watty") + style.dim(" " + details), ""]
        lines += StatusRenderer.lines(for: report, style: style)
        if !report.warnings.isEmpty {
            lines.append("")
            lines += report.warnings.map { style.yellow("warning: \($0)") }
        }
        return lines
    }

    static func line(report: StatusReport, date: Date, timeZone: TimeZone) -> String {
        let level = report.battery.levelPercent.map(String.init) ?? TextFormat.missing
        let state = report.hasBattery ? (report.battery.state?.rawValue ?? TextFormat.missing) : noBatteryState
        let fields = [
            isoTimestamp(date, timeZone: timeZone),
            "level=\(level)",
            "state=\(state)",
            "battery_w=\(TextFormat.signedNumber(report.battery.powerWatts))",
            "system_w=\(TextFormat.number(report.power.systemLoadWatts))"
        ]
        return fields.joined(separator: " ")
    }

    private static func isoTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
