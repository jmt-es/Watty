import SwiftUI
import WattyCore

struct PowerFlowView: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        let reading = PowerFlowReading(snapshot: model.snapshot)

        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Power Flow")

            HStack(spacing: 10) {
                PowerNode(
                    icon: "powerplug.fill",
                    title: model.hasBattery ? "Adapter" : "Power",
                    value: adapterValue(reading),
                    detail: adapterDetail(reading),
                    tint: reading.onAdapter ? .yellow : .secondary,
                    spokenValue: adapterSpokenValue(reading)
                )

                FlowArrow(direction: reading.adapterIsFeedingSystem ? .right : .none, tint: .green)

                PowerNode(
                    icon: model.hasBattery ? "laptopcomputer" : "desktopcomputer",
                    title: "System",
                    value: ValueFormat.watts(reading.systemLoadWatts),
                    detail: String(localized: "load"),
                    tint: .teal,
                    spokenValue: reading.systemLoadWatts.map(ValueFormat.spokenWatts) ?? String(localized: "unavailable")
                )

                if model.hasBattery {
                    FlowArrow(direction: arrowDirection(reading), tint: arrowTint(reading))

                    PowerNode(
                        icon: model.snapshot.chargeState == .charging ? "battery.100.bolt" : "battery.100",
                        title: "Battery",
                        value: ValueFormat.signedWatts(reading.batteryWatts),
                        detail: batteryDetail(reading),
                        tint: batteryTint,
                        spokenValue: batterySpokenValue(reading)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .panelSection()
    }

    private func adapterValue(_ reading: PowerFlowReading) -> String {
        guard reading.onAdapter else { return ValueFormat.missing }
        return ValueFormat.watts(reading.adapterInputWatts)
    }

    private func adapterDetail(_ reading: PowerFlowReading) -> String {
        guard reading.onAdapter else { return String(localized: "unplugged") }
        if let rated = reading.adapterRatedWatts { return String(localized: "\(rated) W max") }
        return String(localized: "connected")
    }

    private func adapterSpokenValue(_ reading: PowerFlowReading) -> String {
        guard reading.onAdapter else { return String(localized: "unplugged") }
        guard let input = reading.adapterInputWatts else { return String(localized: "connected") }
        if let rated = reading.adapterRatedWatts {
            return String(localized: "\(ValueFormat.spokenWatts(input)), \(rated) watts maximum")
        }
        return ValueFormat.spokenWatts(input)
    }

    private func arrowDirection(_ reading: PowerFlowReading) -> FlowArrow.Direction {
        switch reading.batteryDirection {
        case .charging: return .right
        case .discharging, .draining: return .left
        case .idle: return .none
        }
    }

    private func arrowTint(_ reading: PowerFlowReading) -> Color {
        switch reading.batteryDirection {
        case .discharging, .draining: return .orange
        case .charging, .idle: return .green
        }
    }

    private func batteryDetail(_ reading: PowerFlowReading) -> String {
        switch reading.batteryDirection {
        case .charging: return String(localized: "charging")
        case .discharging: return String(localized: "discharging")
        case .draining: return String(localized: "draining")
        case .idle: return String(localized: "idle")
        }
    }

    private func batterySpokenValue(_ reading: PowerFlowReading) -> String {
        let watts = ValueFormat.spokenWatts(abs(reading.batteryWatts ?? 0))
        switch reading.batteryDirection {
        case .charging: return String(localized: "Charging at \(watts)")
        case .discharging: return String(localized: "Discharging at \(watts)")
        case .draining:
            guard reading.batteryWatts != nil else { return String(localized: "draining") }
            return String(localized: "Draining at \(watts)")
        case .idle: return String(localized: "idle")
        }
    }

    private var batteryTint: Color {
        switch model.snapshot.chargeState {
        case .charging, .charged: return .green
        case .pluggedInNotCharging: return .secondary
        case .pluggedInDraining, .onBattery: return .orange
        case .unknown: return .secondary
        }
    }
}

private struct PowerNode: View {
    private static let width: CGFloat = 80
    private static let height: CGFloat = 64

    let icon: String
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let tint: Color
    let spokenValue: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(spokenValue)
    }
}

private struct FlowArrow: View {
    enum Direction {
        case right
        case left
        case none
    }

    let direction: Direction
    let tint: Color

    var body: some View {
        Image(systemName: direction == .left ? "arrow.left" : "arrow.right")
            .font(.caption)
            .foregroundStyle(direction == .none ? Color.secondary.opacity(0.35) : tint)
            .frame(width: 14)
            .accessibilityHidden(true)
    }
}
