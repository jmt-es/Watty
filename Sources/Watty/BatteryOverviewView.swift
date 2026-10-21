import SwiftUI
import WattyCore

struct BatteryOverviewView: View {
    static let chartHeight: CGFloat = 74

    @EnvironmentObject var model: BatteryModel
    @AppStorage(PreferenceKey.batteryChartRange) private var range: BatteryChartRange = .sixHours

    var body: some View {
        let windowEnd = BatteryChartData.windowEnd(for: model.now)
        let visibleSamples = BatteryChartData.visibleSamples(model.historySamples, range: range, windowEnd: windowEnd)

        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(levelText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.snapshot.chargeState.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    Text(model.snapshot.timeRemaining.localizedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                BatteryLevelRing(
                    level: model.snapshot.level,
                    tint: ringTint,
                    isCharging: model.snapshot.chargeState == .charging
                )
            }

            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    SectionTitle("History")
                    if visibleSamples.contains(where: \.isCharging) {
                        ChargingLegend()
                    }
                    Spacer()
                    Picker("History range", selection: $range) {
                        ForEach(BatteryChartRange.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()
                }

                BatteryHistoryChart(samples: visibleSamples, range: range, windowEnd: windowEnd)
                    .equatable()
                    .frame(height: Self.chartHeight)
            }
        }
        .panelSection()
    }

    private var levelText: String {
        model.snapshot.isEmpty ? "--%" : ValueFormat.percent(model.snapshot.level)
    }

    private var ringTint: Color {
        switch model.snapshot.chargeState {
        case .charging, .charged: return .green
        case .pluggedInNotCharging: return .yellow
        case .onBattery: return model.snapshot.level <= BatteryThreshold.lowLevel ? .orange : .teal
        case .unknown: return .secondary
        }
    }

    private var statusColor: Color {
        switch model.snapshot.chargeState {
        case .charging, .charged: return .green
        case .pluggedInNotCharging: return .yellow
        case .onBattery: return model.snapshot.level <= BatteryThreshold.lowLevel ? .orange : .primary
        case .unknown: return .secondary
        }
    }
}

private struct ChargingLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(BatteryChartPalette.charging)
                .frame(width: 6, height: 6)
            Text("Charging")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
