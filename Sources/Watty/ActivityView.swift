import SwiftUI
import WattyCore

struct ActivityView: View {
    @EnvironmentObject var model: BatteryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Activity")
                Spacer()
                Text(temperatureText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(temperatureHelp)
                    .accessibilityLabel("SoC temperature")
                    .accessibilityValue(temperatureSpokenValue)
            }

            HStack(alignment: .top, spacing: 12) {
                MiniChart(
                    title: "CPU",
                    valueText: ValueFormat.percent(model.stats?.cpu?.totalPercent),
                    detail: cpuDetail,
                    points: model.statsHistory.compactMap { sample in
                        sample.cpu.map { (sample.date, $0.totalPercent) }
                    },
                    color: .blue,
                    now: model.now
                )
                MiniChart(
                    title: "Memory",
                    valueText: ValueFormat.percent(model.stats?.memory?.usedPercent),
                    detail: memoryDetail,
                    points: model.statsHistory.compactMap { sample in
                        sample.memory.map { (sample.date, $0.usedPercent) }
                    },
                    color: memoryColor,
                    now: model.now
                )
            }
        }
        .panelSection()
    }

    private var temperatureText: String {
        guard let soc = model.stats?.temperature?.socMaxCelsius else {
            return String(localized: "SoC \(ValueFormat.missing)")
        }
        return String(localized: "SoC \(ValueFormat.wholeCelsius(soc))")
    }

    private var temperatureSpokenValue: String {
        guard let soc = model.stats?.temperature?.socMaxCelsius else { return String(localized: "unavailable") }
        return String(localized: "\(ValueFormat.decimal(soc.rounded(), fractionDigits: 0)) degrees Celsius")
    }

    private var temperatureHelp: String {
        guard let temperature = model.stats?.temperature else { return String(localized: "SoC temperature unavailable") }
        let hottest = ValueFormat.celsius(temperature.socMaxCelsius)
        let average = ValueFormat.celsius(temperature.socAverageCelsius)
        return String(localized: "Hottest die sensor \(hottest) · average \(average) over \(temperature.sensorCount) sensors")
    }

    private var cpuDetail: String {
        guard let cpu = model.stats?.cpu else { return String(localized: "Measuring") }
        return String(localized: "user \(ValueFormat.percent(cpu.userPercent)) · sys \(ValueFormat.percent(cpu.systemPercent))")
    }

    private var memoryDetail: String {
        guard let memory = model.stats?.memory else { return String(localized: "Measuring") }
        let used = ValueFormat.bytes(memory.usedBytes)
        let total = ValueFormat.bytes(memory.totalBytes)
        if memory.swapUsedBytes > 0 {
            return String(localized: "\(used) of \(total) · swap \(ValueFormat.bytes(memory.swapUsedBytes))")
        }
        return String(localized: "\(used) of \(total)")
    }

    private var memoryColor: Color {
        guard let percent = model.stats?.memory?.usedPercent else { return .purple }
        if percent < 70 { return .purple }
        if percent < 90 { return .orange }
        return .red
    }
}

private struct MiniChart: View {
    let title: LocalizedStringKey
    let valueText: String
    let detail: String
    let points: [(Date, Double)]
    let color: Color
    let now: Date

    private static let height: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.08))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                    if visiblePoints(in: geometry.size).count > 1 {
                        fillPath(in: geometry.size)
                            .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        linePath(in: geometry.size)
                            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    } else {
                        Text("Collecting")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: Self.height)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(String(localized: "\(valueText), \(detail)"))
    }

    private var window: TimeInterval {
        guard let oldest = points.first?.0 else { return RefreshCadence.statsMinimumWindow }
        let elapsed = now.timeIntervalSince(oldest)
        return min(RefreshCadence.statsWindow, max(RefreshCadence.statsMinimumWindow, elapsed))
    }

    private func visiblePoints(in size: CGSize) -> [CGPoint] {
        let window = self.window
        return points.compactMap { date, value in
            let age = now.timeIntervalSince(date)
            guard age >= 0, age <= window else { return nil }
            let x = size.width * CGFloat(1 - age / window)
            let y = size.height * CGFloat(1 - min(max(value, 0), 100) / 100)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            let visible = visiblePoints(in: size)
            guard let first = visible.first else { return }
            path.move(to: CGPoint(x: 0, y: first.y))
            for point in visible {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        let visible = visiblePoints(in: size)
        var path = linePath(in: size)
        guard let last = visible.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
