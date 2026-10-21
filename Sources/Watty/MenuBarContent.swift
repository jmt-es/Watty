import Foundation
import WattyCore

struct MenuBarContent: Equatable {
    static let pendingText = "--"
    static let pendingClock = "--:--"
    static let cpuSymbol = "cpu"

    let symbolName: String
    let text: String?
    let accessibilityLabel: String
    let accessibilityValue: String?

    init(snapshot: BatterySnapshot, cpuPercent: Double?, display: MenuBarDisplay) {
        guard snapshot.hasBattery else {
            let cpuText = cpuPercent.map { ValueFormat.percent($0) }
            symbolName = Self.cpuSymbol
            text = display == .iconOnly ? nil : (cpuText ?? Self.pendingText)
            accessibilityLabel = cpuText.map { String(localized: "CPU usage \($0)") } ?? String(localized: "CPU usage unavailable")
            accessibilityValue = nil
            return
        }

        symbolName = Self.batterySymbol(for: snapshot)
        accessibilityLabel = Self.batteryDescription(for: snapshot)
        switch display {
        case .percentage:
            text = Self.percentText(for: snapshot)
            accessibilityValue = nil
        case .timeRemaining:
            let clock = Self.clockText(for: snapshot)
            text = clock ?? Self.percentText(for: snapshot)
            accessibilityValue = clock.flatMap { Self.spokenTime($0, for: snapshot) }
        case .power:
            let watts = Self.menuBarWatts(for: snapshot)
            text = watts.map { ValueFormat.watts($0) } ?? ValueFormat.missing
            accessibilityValue = watts.map { ValueFormat.spokenWatts($0) }
        case .iconOnly:
            text = nil
            accessibilityValue = nil
        }
    }

    static func batterySymbol(for snapshot: BatterySnapshot) -> String {
        switch snapshot.chargeState {
        case .charging: return "battery.100.bolt"
        case .charged, .pluggedInNotCharging: return "battery.100"
        case .unknown: return "battery.0"
        case .onBattery:
            if snapshot.level <= 10 { return "battery.0" }
            if snapshot.level <= 35 { return "battery.25" }
            if snapshot.level <= 65 { return "battery.50" }
            if snapshot.level <= 90 { return "battery.75" }
            return "battery.100"
        }
    }

    private static func percentText(for snapshot: BatterySnapshot) -> String {
        snapshot.isEmpty ? pendingText : ValueFormat.percent(snapshot.level)
    }

    private static func clockText(for snapshot: BatterySnapshot) -> String? {
        switch snapshot.chargeState {
        case .onBattery:
            return snapshot.timeToEmptyMinutes.map(BatterySnapshot.clockText(minutes:)) ?? pendingClock
        case .charging:
            return snapshot.timeToFullMinutes.map(BatterySnapshot.clockText(minutes:)) ?? pendingClock
        case .charged, .pluggedInNotCharging, .unknown:
            return nil
        }
    }

    private static func menuBarWatts(for snapshot: BatterySnapshot) -> Double? {
        if snapshot.chargeState == .onBattery {
            return snapshot.batteryPowerWatts.map(abs)
        }
        return snapshot.systemPowerWatts
    }

    private static func spokenTime(_ clock: String, for snapshot: BatterySnapshot) -> String? {
        guard clock != pendingClock else { return nil }
        return snapshot.chargeState == .charging
            ? String(localized: "\(clock) until full")
            : String(localized: "\(clock) remaining")
    }

    private static func batteryDescription(for snapshot: BatterySnapshot) -> String {
        let percent = ValueFormat.percent(snapshot.level)
        switch snapshot.chargeState {
        case .charging: return String(localized: "Battery \(percent), charging")
        case .charged: return String(localized: "Battery \(percent), fully charged")
        case .pluggedInNotCharging: return String(localized: "Battery \(percent), plugged in, not charging")
        case .onBattery: return String(localized: "Battery \(percent), on battery")
        case .unknown: return String(localized: "Battery, reading")
        }
    }
}
