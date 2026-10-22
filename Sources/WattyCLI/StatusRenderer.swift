import Foundation
import WattyCore

struct KeyValueRow: Equatable {
    let key: String
    let value: String
}

enum KeyValueLayout {
    private static let columnGap = "  "

    static func lines(_ rows: [KeyValueRow], style: TextStyle) -> [String] {
        let keyWidth = rows.map { $0.key.count }.max() ?? 0
        return rows.map { row in
            let padding = String(repeating: " ", count: keyWidth - row.key.count)
            return style.bold(row.key) + padding + columnGap + row.value
        }
    }
}

enum StatusRenderer {
    private static let criticalBatteryLevel = 10
    private static let lowBatteryLevel = 20
    private static let healthyCondition = "Normal"

    static func lines(for report: StatusReport, style: TextStyle) -> [String] {
        KeyValueLayout.lines(rows(for: report, style: style), style: style)
    }

    static func rows(for report: StatusReport, style: TextStyle) -> [KeyValueRow] {
        var rows = [KeyValueRow(key: "Battery", value: batterySummary(report, style: style))]
        if report.hasBattery {
            rows += batteryRows(report, style: style)
        }
        rows.append(KeyValueRow(key: "Power mode", value: powerModeText(report.power, style: style)))
        rows += systemRows(report.system, style: style)
        return rows
    }

    private static func batteryRows(_ report: StatusReport, style: TextStyle) -> [KeyValueRow] {
        let battery = report.battery
        let power = report.power
        return [
            KeyValueRow(key: "Power source", value: sourceText(power, style: style)),
            KeyValueRow(key: "System input", value: known(TextFormat.watts(power.systemInputWatts), style: style)),
            KeyValueRow(key: "System load", value: known(TextFormat.watts(power.systemLoadWatts), style: style)),
            KeyValueRow(key: "Battery power", value: batteryPowerText(report, style: style)),
            KeyValueRow(key: "Voltage", value: known(TextFormat.volts(battery.voltageVolts), style: style)),
            KeyValueRow(key: "Amperage", value: known(TextFormat.signedAmps(battery.amperageAmps), style: style)),
            KeyValueRow(key: "Battery temp", value: known(TextFormat.celsius(battery.temperatureCelsius), style: style)),
            KeyValueRow(key: "Cycles", value: known(TextFormat.integer(battery.cycleCount), style: style)),
            KeyValueRow(key: "Max capacity", value: known(TextFormat.percent(battery.maximumCapacityPercent), style: style)),
            KeyValueRow(key: "Condition", value: conditionText(battery, style: style))
        ]
    }

    private static func systemRows(_ system: StatusReport.SystemStatus, style: TextStyle) -> [KeyValueRow] {
        [
            KeyValueRow(key: "SoC temp", value: known(TextFormat.celsius(system.socTemperatureCelsius), style: style)),
            KeyValueRow(key: "CPU", value: cpuText(system, style: style)),
            KeyValueRow(key: "Memory", value: memoryText(system, style: style))
        ]
    }

    private static func batterySummary(_ report: StatusReport, style: TextStyle) -> String {
        guard report.hasBattery else { return "none detected" }
        let battery = report.battery
        var parts = [levelText(report, style: style)]
        if isDrainingOnAdapter(report) {
            parts.append(style.yellow("Plugged in, draining"))
            parts.append(adapterCannotKeepUpText(report.power.adapterRatedWatts))
            return parts.joined(separator: TextFormat.separator)
        }
        if let state = battery.state {
            parts.append(stateText(state, style: style))
        }
        if let time = timeText(battery) {
            parts.append(time)
        }
        return parts.joined(separator: TextFormat.separator)
    }

    private static func isDrainingOnAdapter(_ report: StatusReport) -> Bool {
        report.power.source == .adapter && report.battery.netFlow == .draining
    }

    private static func adapterCannotKeepUpText(_ ratedWatts: Int?) -> String {
        guard let ratedWatts, ratedWatts > 0 else { return "the adapter can't keep up" }
        return "the \(ratedWatts) W adapter can't keep up"
    }

    private static func levelText(_ report: StatusReport, style: TextStyle) -> String {
        let battery = report.battery
        guard let level = battery.levelPercent else { return style.dim(TextFormat.missing) }
        let text = "\(level)%"
        if isDrainingOnAdapter(report) { return lowLevelStyled(text, level: level, style: style) }
        switch battery.state {
        case .onBattery?:
            return lowLevelStyled(text, level: level, style: style)
        case .charging?, .charged?:
            return style.green(text)
        default:
            return text
        }
    }

    private static func lowLevelStyled(_ text: String, level: Int, style: TextStyle) -> String {
        if level <= criticalBatteryLevel { return style.red(text) }
        if level <= lowBatteryLevel { return style.yellow(text) }
        return text
    }

    private static func stateText(_ state: ReportChargeState, style: TextStyle) -> String {
        switch state {
        case .charging: return style.green("Charging")
        case .charged: return style.green("Charged")
        case .pluggedInNotCharging: return "Plugged in, not charging"
        case .onBattery: return "On battery"
        }
    }

    private static func timeText(_ battery: StatusReport.BatteryStatus) -> String? {
        switch battery.state {
        case .charging?:
            return battery.timeToFullMinutes.map { "\(TextFormat.clock(minutes: $0)) to full" }
        case .onBattery?:
            return battery.timeToEmptyMinutes.map { "\(TextFormat.clock(minutes: $0)) left" }
        default:
            return nil
        }
    }

    private static func sourceText(_ power: StatusReport.PowerStatus, style: TextStyle) -> String {
        switch power.source {
        case .adapter?:
            guard let watts = power.adapterRatedWatts else { return "Power adapter" }
            return "Power adapter\(TextFormat.separator)\(watts) W rated"
        case .battery?:
            return "Battery"
        case nil:
            return style.dim(TextFormat.missing)
        }
    }

    private static func batteryPowerText(_ report: StatusReport, style: TextStyle) -> String {
        if isDrainingOnAdapter(report) {
            guard let average = report.battery.averagePowerWatts else {
                return TextFormat.signedWatts(report.battery.powerWatts)
            }
            return TextFormat.signedWatts(average) + TextFormat.separator + style.yellow("draining")
        }
        guard let watts = report.battery.powerWatts else { return style.dim(TextFormat.missing) }
        let value = TextFormat.signedWatts(watts)
        guard let flow = TextFormat.batteryFlow(watts) else { return value }
        let colored = watts < 0 ? style.yellow(flow) : (watts > 0 ? style.green(flow) : flow)
        return value + TextFormat.separator + colored
    }

    private static func conditionText(_ battery: StatusReport.BatteryStatus, style: TextStyle) -> String {
        guard let condition = battery.condition else { return style.dim(TextFormat.missing) }
        return condition == healthyCondition ? condition : style.yellow(condition)
    }

    private static func powerModeText(_ power: StatusReport.PowerStatus, style: TextStyle) -> String {
        var parts: [String] = []
        if let mode = power.mode {
            parts.append(modeTitle(mode))
        }
        if let lowPower = power.lowPowerModeActive {
            parts.append("Low Power Mode \(lowPower ? "on" : "off")")
        }
        return parts.isEmpty ? style.dim(TextFormat.missing) : parts.joined(separator: TextFormat.separator)
    }

    private static func modeTitle(_ mode: ReportPowerMode) -> String {
        switch mode {
        case .automatic: return PowerMode.automatic.longTitle
        case .lowPower: return PowerMode.lowPower.longTitle
        case .highPower: return PowerMode.highPower.longTitle
        }
    }

    private static func cpuText(_ system: StatusReport.SystemStatus, style: TextStyle) -> String {
        guard let total = system.cpuPercent else { return style.dim(TextFormat.missing) }
        var parts = [TextFormat.percent(total)]
        if let user = system.cpuUserPercent {
            parts.append("user \(TextFormat.percent(user))")
        }
        if let kernel = system.cpuSystemPercent {
            parts.append("system \(TextFormat.percent(kernel))")
        }
        return parts.joined(separator: TextFormat.separator)
    }

    private static func memoryText(_ system: StatusReport.SystemStatus, style: TextStyle) -> String {
        guard let percent = system.memoryPercent else { return style.dim(TextFormat.missing) }
        var parts = [TextFormat.percent(percent)]
        if let used = system.memoryUsedBytes, let total = system.memoryTotalBytes {
            parts.append("\(TextFormat.bytes(used)) of \(TextFormat.bytes(total))")
        }
        if let swap = system.swapUsedBytes, swap > 0 {
            parts.append("swap \(TextFormat.bytes(swap))")
        }
        return parts.joined(separator: TextFormat.separator)
    }

    private static func known(_ text: String, style: TextStyle) -> String {
        text == TextFormat.missing ? style.dim(text) : text
    }
}
