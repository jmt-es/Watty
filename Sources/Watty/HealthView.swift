import SwiftUI
import WattyCore

struct HealthView: View {
    @EnvironmentObject var model: BatteryModel
    @AppStorage(PreferenceKey.healthExpanded) private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    SectionTitle("Health")
                    Spacer()
                    if !expanded {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse health details" : "Expand health details")
            .accessibilityLabel("Health")
            .accessibilityValue(expanded ? Text("Expanded") : Text(summary))
            .accessibilityHint(expanded ? "Collapses the health details" : "Expands the health details")

            if expanded {
                Grid(horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow(alignment: .top) {
                        MetricCell("Cycles", value: ValueFormat.integer(model.snapshot.cycleCount))
                        MetricCell("Capacity", value: ValueFormat.percent(model.snapshot.maximumCapacityPercent))
                        MetricCell("Battery temp", value: ValueFormat.celsius(model.snapshot.temperatureCelsius))
                    }
                    GridRow(alignment: .top) {
                        MetricCell("Voltage", value: ValueFormat.volts(model.snapshot.voltageVolts))
                        MetricCell("Current", value: ValueFormat.amps(model.snapshot.amperageAmps))
                        MetricCell("Condition", value: model.snapshot.condition.map(BatteryCondition.localizedText) ?? ValueFormat.missing)
                    }
                }
            }
        }
        .panelSection()
    }

    private var summary: String {
        [
            model.snapshot.cycleCount.map { String(localized: "\($0) cycles") },
            model.snapshot.maximumCapacityPercent.map { ValueFormat.percent($0) },
            model.snapshot.condition.map(BatteryCondition.localizedText),
            model.snapshot.temperatureCelsius.map { ValueFormat.celsius($0) }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private struct MetricCell: View {
    let label: LocalizedStringKey
    let value: String

    init(_ label: LocalizedStringKey, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(width: 94, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(value)
    }
}
