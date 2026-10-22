import Foundation

public enum PluggedInDrainPeriods {
    static let minimumFallPoints = 3.0
    static let smoothingHalfWindow: TimeInterval = 90
    static let maximumGap: TimeInterval = 600

    public static func detect(in samples: [BatteryHistorySample]) -> [DateInterval] {
        adapterRuns(in: samples.sorted { $0.date < $1.date }).flatMap(fallingPeriods(in:))
    }

    private static func adapterRuns(in samples: [BatteryHistorySample]) -> [[BatteryHistorySample]] {
        var runs: [[BatteryHistorySample]] = []
        var current: [BatteryHistorySample] = []

        func closeRun() {
            if current.count > 1 { runs.append(current) }
            current = []
        }

        for sample in samples {
            guard sample.onAdapter else {
                closeRun()
                continue
            }
            if let last = current.last, sample.date.timeIntervalSince(last.date) > maximumGap { closeRun() }
            current.append(sample)
        }
        closeRun()
        return runs
    }

    private static func fallingPeriods(in run: [BatteryHistorySample]) -> [DateInterval] {
        let pivots = LevelSwings.pivots(in: smoothedLevels(of: run), minimumSwing: minimumFallPoints)
        return zip(pivots, pivots.dropFirst()).compactMap { start, end in
            guard start.isPeak, !end.isPeak else { return nil }
            return DateInterval(start: run[start.index].date, end: run[end.index].date)
        }
    }

    private static func smoothedLevels(of run: [BatteryHistorySample]) -> [Double] {
        var first = 0
        var last = 0
        return run.map { sample in
            while run[first].date < sample.date.addingTimeInterval(-smoothingHalfWindow) { first += 1 }
            while last + 1 < run.count, run[last + 1].date <= sample.date.addingTimeInterval(smoothingHalfWindow) { last += 1 }
            return median(run[first...last].map { Double($0.level) })
        }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
