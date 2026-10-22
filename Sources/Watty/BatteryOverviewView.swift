import SwiftUI
import WattyCore

struct BatteryOverviewView: View {
    static let chartHeight: CGFloat = 74

    @EnvironmentObject var model: BatteryModel
    @AppStorage(PreferenceKey.batteryChartRange) private var range: BatteryChartRange = .sixHours

    var body: some View {
        let windowEnd = BatteryChartData.windowEnd(for: model.now)
        let visibleSamples = BatteryChartData.visibleSamples(model.historySamples, range: range, windowEnd: windowEnd)
        let segments = BatteryChartSegment.segments(from: visibleSamples, drainPeriods: model.drainPeriods)

        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text(levelText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.snapshot.chargeState.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(style.textColor)
                    Text(model.snapshot.timeRemaining.localizedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                BatteryLevelRing(level: model.snapshot.level, tint: style.tint, symbol: style.ringSymbol)
            }

            VStack(spacing: 5) {
                HistoryHeader(kinds: BatteryChartSegment.legendKinds(in: segments), range: $range)

                BatteryHistoryChart(samples: visibleSamples, segments: segments, range: range, windowEnd: windowEnd)
                    .equatable()
                    .frame(height: Self.chartHeight)
            }
        }
        .panelSection()
    }

    private var levelText: String {
        model.snapshot.isEmpty ? "--%" : ValueFormat.percent(model.snapshot.level)
    }

    private var style: ChargeStatusStyle {
        ChargeStatusStyle(chargeState: model.snapshot.chargeState, level: model.snapshot.level)
    }
}

private struct HistoryHeader: View {
    let kinds: [BatteryChartSegment.Kind]
    @Binding var range: BatteryChartRange

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                SectionTitle("History")
                ChartLegend(kinds: kinds)
                Spacer(minLength: 0)
                RangePicker(range: $range)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SectionTitle("History")
                    Spacer(minLength: 0)
                    RangePicker(range: $range)
                }
                HStack(spacing: 8) {
                    ChartLegend(kinds: kinds)
                }
            }
        }
    }
}

private struct RangePicker: View {
    @Binding var range: BatteryChartRange

    var body: some View {
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
}

private struct ChartLegend: View {
    let kinds: [BatteryChartSegment.Kind]

    var body: some View {
        ForEach(kinds, id: \.self) { kind in
            if let title = kind.legendTitle {
                HStack(spacing: 4) {
                    Circle()
                        .fill(BatteryChartPalette.line(for: kind))
                        .frame(width: 6, height: 6)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityHidden(true)
            }
        }
    }
}

private extension BatteryChartSegment.Kind {
    var legendTitle: LocalizedStringKey? {
        switch self {
        case .charging: return "Charging"
        case .draining: return "Plugged in, draining"
        case .standard: return nil
        }
    }
}
