import Foundation

struct PowerChunk: Equatable, Sendable {
    let observedAt: Date
    let milliwattTicks: Int64
    let ticks: Int64

    init?(from earlier: PowerAccumulation, to later: PowerAccumulation, observedAt: Date) {
        let ticks = later.ticks - earlier.ticks
        let (milliwattTicks, overflowed) = later.milliwattTicks.subtractingReportingOverflow(earlier.milliwattTicks)
        guard ticks > 0, ticks <= NetFlowRules.Accumulation.maximumChunkTicks, !overflowed else { return nil }
        let meanWatts = Double(milliwattTicks) / Double(ticks) / NetFlowRules.Accumulation.milliwattsPerWatt
        guard abs(meanWatts) <= IoregBatteryInfo.maximumPlausibleBatteryWatts else { return nil }
        self.observedAt = observedAt
        self.milliwattTicks = milliwattTicks
        self.ticks = ticks
    }
}

struct PowerSeries: Equatable, Sendable {
    private static let pointsKeptBeforeTheWindow = 1

    private var points: [TimedValue] = []
    private var chunks: [PowerChunk] = []
    private var baseline: PowerAccumulation?
    private var baselineFollowsABreak = false

    mutating func append(_ point: TimedValue) {
        points.append(point)
        let windowStart = point.date.addingTimeInterval(-NetFlowRules.Power.averagingWindow)
        if let firstInside = points.firstIndex(where: { $0.date >= windowStart }), firstInside > Self.pointsKeptBeforeTheWindow {
            points.removeFirst(firstInside - Self.pointsKeptBeforeTheWindow)
        }
    }

    mutating func observe(_ accumulation: PowerAccumulation, at date: Date) {
        let windowStart = date.addingTimeInterval(-NetFlowRules.Power.averagingWindow)
        chunks.removeAll { $0.observedAt < windowStart }

        guard let previous = baseline else {
            baseline = accumulation
            return
        }
        guard accumulation.ticks >= previous.ticks else {
            baseline = accumulation
            baselineFollowsABreak = true
            return
        }
        guard accumulation.ticks > previous.ticks else { return }

        if !baselineFollowsABreak, let chunk = PowerChunk(from: previous, to: accumulation, observedAt: date) {
            chunks.append(chunk)
        }
        baseline = accumulation
        baselineFollowsABreak = false
    }

    mutating func restart(with accumulation: PowerAccumulation?) {
        points.removeAll()
        chunks.removeAll()
        baseline = accumulation
        baselineFollowsABreak = true
    }

    func average(endingAt end: Date) -> Double? {
        let start = end.addingTimeInterval(-NetFlowRules.Power.averagingWindow)
        let recentChunks = chunks.filter { $0.observedAt >= start }
        if !recentChunks.isEmpty {
            let milliwattTicks = recentChunks.reduce(0.0) { $0 + Double($1.milliwattTicks) }
            let ticks = recentChunks.reduce(0.0) { $0 + Double($1.ticks) }
            return milliwattTicks / ticks / NetFlowRules.Accumulation.milliwattsPerWatt
        }
        guard let mean = TimeWeightedAverage.mean(of: points, from: start, to: end),
              mean.coveredSeconds >= NetFlowRules.Power.minimumInstantaneousSpan else { return nil }
        return mean.value
    }
}
