import Foundation

struct TimedValue: Equatable, Sendable {
    let date: Date
    let value: Double
}

struct TimeWeightedMean: Equatable, Sendable {
    let value: Double
    let coveredSeconds: TimeInterval
}

enum TimeWeightedAverage {
    static func mean(of points: [TimedValue], from start: Date, to end: Date) -> TimeWeightedMean? {
        guard let latest = points.last else { return nil }

        var integral = 0.0
        var covered: TimeInterval = 0
        for (earlier, later) in zip(points, points.dropFirst()) {
            let from = max(earlier.date, start)
            let to = min(later.date, end)
            guard to > from else { continue }
            let valueAtFrom = interpolated(from: earlier, to: later, at: from)
            let valueAtTo = interpolated(from: earlier, to: later, at: to)
            let duration = to.timeIntervalSince(from)
            integral += (valueAtFrom + valueAtTo) / 2 * duration
            covered += duration
        }
        guard covered > 0 else { return TimeWeightedMean(value: latest.value, coveredSeconds: 0) }
        return TimeWeightedMean(value: integral / covered, coveredSeconds: covered)
    }

    private static func interpolated(from earlier: TimedValue, to later: TimedValue, at date: Date) -> Double {
        let total = later.date.timeIntervalSince(earlier.date)
        let elapsed = date.timeIntervalSince(earlier.date)
        return earlier.value + (later.value - earlier.value) * elapsed / total
    }
}
