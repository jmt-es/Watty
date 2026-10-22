import Foundation

enum NetFlowRules {
    enum Continuity {
        static let maximumReadingGap: TimeInterval = 120
        static let maximumGapAfterSeed = BatteryHistoryStore.saveInterval
        static let settlingTime: TimeInterval = 90
    }

    enum Power {
        static let averagingWindow: TimeInterval = 150
        static let minimumInstantaneousSpan: TimeInterval = 30
        static let drainingEnterWatts = -2.0
        static let drainingExitWatts = -0.5
        static let strongDrainingWatts = -5.0
        static let chargingEnterWatts = 0.5
        static let chargingExitWatts = 0.25
    }

    enum Accumulation {
        static let maximumChunkTicks: Int64 = 300
        static let milliwattsPerWatt = 1_000.0
    }

    enum Trend {
        static let window: TimeInterval = 480
        static let bucket: TimeInterval = 15
        static let minimumPoints = 5
        static let minimumSpan: TimeInterval = 180
        static let minimumSeparation: TimeInterval = 120
        static let decisivePointsPerMinute = 0.3
        static let sustainedPointsPerMinute = 0.15
        static let minimumChangePoints = 3.0
    }
}
