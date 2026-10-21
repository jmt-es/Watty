import SwiftUI
import WattyCore

struct EnergyConsumersView: View {
    private static let visibleConsumers = 5

    @EnvironmentObject var model: BatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionTitle("Energy")
                Spacer()
                Text(sampleText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if model.energySample.isEmpty || model.energySample.isWarmingUp {
                placeholder(icon: "hourglass", text: "Measuring per-app CPU")
            } else if model.energySample.failed {
                placeholder(icon: "exclamationmark.triangle", text: "Sampling failed, retrying")
            } else if model.energySample.consumers.isEmpty {
                placeholder(icon: "checkmark.seal", text: "No significant load")
            } else {
                ForEach(model.energySample.consumers.prefix(Self.visibleConsumers)) { consumer in
                    EnergyRow(consumer: consumer)
                }
            }
        }
        .panelSection()
    }

    private var sampleText: String {
        if model.isSamplingEnergy { return String(localized: "Sampling…") }
        guard !model.energySample.isEmpty, !model.energySample.isWarmingUp else { return "" }
        return String(localized: "Sampled \(ValueFormat.relative(model.energySample.sampledAt, now: model.now))")
    }

    private func placeholder(icon: String, text: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

private struct EnergyRow: View {
    let consumer: EnergyConsumer

    var body: some View {
        HStack(spacing: 8) {
            if let icon = consumer.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }

            Text(consumer.name)
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(ValueFormat.cpuPercent(consumer.cpuPercent))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .trailing)

            Text(consumer.memoryBytes > 0 ? ValueFormat.bytes(consumer.memoryBytes) : "")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Circle()
                .fill(color(forCPU: consumer.cpuPercent))
                .frame(width: 7, height: 7)
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(consumer.name)
        .accessibilityValue(spokenValue)
    }

    private var helpText: String {
        let cpu = ValueFormat.cpuPercent(consumer.cpuPercent)
        if consumer.memoryBytes > 0 {
            return String(localized: "\(consumer.name) · CPU \(cpu) · memory \(ValueFormat.bytes(consumer.memoryBytes))")
        }
        return String(localized: "\(consumer.name) · CPU \(cpu) · system process, memory not readable without root")
    }

    private var spokenValue: String {
        let cpu = ValueFormat.cpuPercent(consumer.cpuPercent)
        if consumer.memoryBytes > 0 {
            return String(localized: "CPU \(cpu), memory \(ValueFormat.bytes(consumer.memoryBytes))")
        }
        return String(localized: "CPU \(cpu)")
    }

    private func color(forCPU percent: Double) -> Color {
        if percent < 5 { return .green }
        if percent < 25 { return .orange }
        return .red
    }
}
