import Foundation

struct LevelPoint: Equatable, Sendable {
    let date: Date
    let level: Int
}

struct LevelSeries: Equatable, Sendable {
    private(set) var points: [LevelPoint] = []

    mutating func append(_ point: LevelPoint) {
        if let last = points.last, Self.bucket(of: last.date) == Self.bucket(of: point.date) {
            points[points.count - 1] = point
        } else {
            points.append(point)
        }
        let oldest = point.date.addingTimeInterval(-NetFlowRules.Trend.window)
        points.removeAll { $0.date < oldest }
    }

    mutating func removeAll() {
        points.removeAll()
    }

    private static func bucket(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / NetFlowRules.Trend.bucket).rounded(.down))
    }
}

struct LevelTrend: Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        case falling
        case rising
        case steady
    }

    let pointsPerMinute: Double
    let spanSeconds: TimeInterval

    var changePoints: Double {
        pointsPerMinute * spanSeconds / Self.secondsPerMinute
    }

    var direction: Direction {
        let decisive = NetFlowRules.Trend.decisivePointsPerMinute
        let minimumChange = NetFlowRules.Trend.minimumChangePoints
        if pointsPerMinute <= -decisive, changePoints <= -minimumChange { return .falling }
        if pointsPerMinute >= decisive, changePoints >= minimumChange { return .rising }
        return .steady
    }

    var isStillFalling: Bool {
        pointsPerMinute <= -NetFlowRules.Trend.sustainedPointsPerMinute
    }

    private static let secondsPerMinute = 60.0

    static func estimate(from series: LevelSeries) -> LevelTrend? {
        let points = series.points
        guard points.count >= NetFlowRules.Trend.minimumPoints,
              let first = points.first, let last = points.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= NetFlowRules.Trend.minimumSpan else { return nil }

        var slopes: [Double] = []
        for (index, earlier) in points.enumerated() {
            for later in points[(index + 1)...] {
                let separation = later.date.timeIntervalSince(earlier.date)
                guard separation >= NetFlowRules.Trend.minimumSeparation else { continue }
                slopes.append(Double(later.level - earlier.level) / (separation / secondsPerMinute))
            }
        }
        guard let slope = median(slopes) else { return nil }
        return LevelTrend(pointsPerMinute: slope, spanSeconds: span)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
