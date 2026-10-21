import Charts
import SwiftUI
import WattyCore

struct BatteryHistoryChart: View, Equatable {
    static let axisFontSize: CGFloat = 9
    static let lineWidth: CGFloat = 1.8
    static let yAxisMarks = [0, 50, 100]

    let samples: [BatteryHistorySample]
    let range: BatteryChartRange
    let windowEnd: Date

    private var windowStart: Date {
        windowEnd.addingTimeInterval(-range.duration)
    }

    var body: some View {
        let segments = BatteryChartSegment.segments(from: samples)

        Chart {
            ForEach(segments.filter(\.isCharging)) { segment in
                if let first = segment.samples.first, let last = segment.samples.last, last.date > first.date {
                    RectangleMark(
                        xStart: .value("Charging from", first.date),
                        xEnd: .value("Charging until", last.date),
                        yStart: .value("Minimum", 0),
                        yEnd: .value("Maximum", 100)
                    )
                    .foregroundStyle(BatteryChartPalette.charging.opacity(0.13))
                }
            }

            ForEach(segments) { segment in
                ForEach(segment.samples) { sample in
                    AreaMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery", sample.level),
                        series: .value("Segment", segment.id),
                        stacking: .unstacked
                    )
                    .foregroundStyle(BatteryChartPalette.fill(isCharging: segment.isCharging))

                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery", sample.level),
                        series: .value("Segment", segment.id)
                    )
                    .foregroundStyle(BatteryChartPalette.line(isCharging: segment.isCharging))
                    .lineStyle(StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
                }
            }

            if let latest = samples.last {
                PointMark(
                    x: .value("Time", latest.date),
                    y: .value("Battery", latest.level)
                )
                .symbolSize(30)
                .foregroundStyle(BatteryChartPalette.line(isCharging: latest.isCharging))
            }
        }
        .chartXScale(domain: windowStart...windowEnd)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: BatteryChartData.tickDates(range: range, start: windowStart, end: windowEnd)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel(format: timeFormat)
                    .font(.system(size: Self.axisFontSize))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: Self.yAxisMarks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.28))
                AxisValueLabel {
                    if let level = value.as(Int.self) {
                        Text(ValueFormat.percent(level))
                            .font(.system(size: Self.axisFontSize))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.05)))
        }
        .overlay {
            if samples.count < 2 {
                Text("Collecting history…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery level history"))
        .accessibilityValue(accessibilitySummary)
        .accessibilityAddTraits(.isImage)
    }

    private var timeFormat: Date.FormatStyle {
        range == .oneHour ? .dateTime.hour().minute() : .dateTime.hour()
    }

    private var accessibilitySummary: String {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else {
            return String(localized: "Not enough data yet")
        }
        let lowest = samples.map(\.level).min() ?? last.level
        let highest = samples.map(\.level).max() ?? last.level
        return String(localized: "\(range.spokenName): from \(ValueFormat.percent(first.level)) to \(ValueFormat.percent(last.level)), lowest \(ValueFormat.percent(lowest)), highest \(ValueFormat.percent(highest))")
    }
}

enum BatteryChartPalette {
    static let charging = Color.green
    static let discharging = Color.teal

    static func line(isCharging: Bool) -> Color {
        isCharging ? charging : discharging
    }

    static func fill(isCharging: Bool) -> LinearGradient {
        let color = line(isCharging: isCharging)
        return LinearGradient(
            colors: [color.opacity(0.26), color.opacity(0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
