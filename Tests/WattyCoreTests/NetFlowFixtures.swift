import Foundation
@testable import WattyCore

enum NetFlowFixtures {
    static let origin = Date(timeIntervalSince1970: 1_800_000_000)
    static let visibleCadence: TimeInterval = 2
    static let hiddenCadence: TimeInterval = 30
    static let visibleWarmUpReadings = Int(NetFlowRules.Power.minimumInstantaneousSpan / visibleCadence)

    static let incidentWatts: [Double] = [
        -18, -22, -25, -15, -20, -19, -23, -17, -21, 4.8, -24, -16, -20, -22, -18, -19, 3.1, -21, -25, -17
    ]
    private static let incidentLevelJitter = [0, 1, 0, -1, 0, 1, -1, 0, 1, 0, -1, -1, 0]
    private static let incidentStartLevel = 27.0
    private static let incidentPointsPerMinute = 0.95
    private static let incidentFloorLevel = 5

    static func reading(
        at seconds: TimeInterval,
        watts: Double?,
        level: Int = 50,
        onAdapter: Bool = true,
        reportsCharging: Bool = true
    ) -> NetFlowReading {
        NetFlowReading(
            date: origin.addingTimeInterval(seconds),
            batteryWatts: watts,
            level: level,
            onAdapter: onAdapter,
            reportsCharging: reportsCharging
        )
    }

    static func incidentReadings(through seconds: TimeInterval, every cadence: TimeInterval) -> [NetFlowReading] {
        let count = Int(seconds / cadence)
        return (0...count).map { index in
            let elapsed = Double(index) * cadence
            let fallen = Int((elapsed / 60 * incidentPointsPerMinute).rounded())
            let jitter = incidentLevelJitter[index % incidentLevelJitter.count]
            let level = max(incidentFloorLevel, Int(incidentStartLevel) - fallen + jitter)
            return reading(at: elapsed, watts: incidentWatts[index % incidentWatts.count], level: level)
        }
    }

    static func steadyReadings(
        from start: TimeInterval,
        through end: TimeInterval,
        every cadence: TimeInterval,
        watts: Double?,
        level: @escaping (TimeInterval) -> Int = { _ in 50 },
        onAdapter: Bool = true,
        reportsCharging: Bool = true
    ) -> [NetFlowReading] {
        let count = Int((end - start) / cadence)
        return (0...count).map { index in
            let elapsed = start + Double(index) * cadence
            return reading(at: elapsed, watts: watts, level: level(elapsed), onAdapter: onAdapter, reportsCharging: reportsCharging)
        }
    }

    static func flows(_ readings: [NetFlowReading], using estimator: inout NetFlowEstimator) -> [NetFlow?] {
        readings.map { estimator.record($0).flow }
    }

    static func changeCount(in flows: [NetFlow?]) -> Int {
        zip(flows, flows.dropFirst()).filter { $0 != $1 }.count
    }
}
