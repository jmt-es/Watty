import Foundation
import SwiftUI
import WattyCore

enum BatteryChartRange: Int, CaseIterable, Identifiable {
    case oneHour = 1
    case sixHours = 6
    case twentyFourHours = 24

    static let maximumPoints = 360

    var id: Int { rawValue }

    var duration: TimeInterval {
        TimeInterval(rawValue) * 3_600
    }

    var label: LocalizedStringKey {
        switch self {
        case .oneHour: return "1 h"
        case .sixHours: return "6 h"
        case .twentyFourHours: return "24 h"
        }
    }

    var spokenName: String {
        switch self {
        case .oneHour: return String(localized: "Last hour")
        case .sixHours: return String(localized: "Last 6 hours")
        case .twentyFourHours: return String(localized: "Last 24 hours")
        }
    }

    var tickUnit: Calendar.Component {
        self == .oneHour ? .minute : .hour
    }

    var tickStep: Int {
        switch self {
        case .oneHour: return 15
        case .sixHours: return 2
        case .twentyFourHours: return 6
        }
    }
}

struct BatteryChartSegment: Identifiable, Equatable {
    enum Kind: Hashable {
        case charging
        case draining
        case standard
    }

    static let gapThreshold: TimeInterval = 10 * 60

    let id: Int
    let kind: Kind
    let samples: [BatteryHistorySample]

    static func segments(from samples: [BatteryHistorySample], drainPeriods: [DateInterval] = []) -> [BatteryChartSegment] {
        var segments: [BatteryChartSegment] = []
        var current: [BatteryHistorySample] = []
        var currentKind = Kind.standard

        func flush() {
            guard !current.isEmpty else { return }
            segments.append(BatteryChartSegment(id: segments.count, kind: currentKind, samples: current))
        }

        for sample in samples {
            guard let last = current.last, sample.date.timeIntervalSince(last.date) <= gapThreshold else {
                flush()
                current = [sample]
                currentKind = kind(of: sample, drainPeriods: drainPeriods)
                continue
            }

            let sampleKind = kind(of: sample, drainPeriods: drainPeriods)
            if sampleKind == currentKind {
                current.append(sample)
            } else {
                flush()
                current = [last, sample]
                currentKind = sampleKind
            }
        }
        flush()
        return segments
    }

    static func legendKinds(in segments: [BatteryChartSegment]) -> [Kind] {
        [Kind.charging, Kind.draining].filter { kind in segments.contains { $0.kind == kind } }
    }

    private static func kind(of sample: BatteryHistorySample, drainPeriods: [DateInterval]) -> Kind {
        if sample.onAdapter, drainPeriods.contains(where: { $0.contains(sample.date) }) { return .draining }
        return sample.isCharging ? .charging : .standard
    }
}

enum BatteryChartData {
    static let edgeClearanceFraction = 0.07

    static func visibleSamples(
        _ samples: [BatteryHistorySample],
        range: BatteryChartRange,
        windowEnd: Date
    ) -> [BatteryHistorySample] {
        let start = windowEnd.addingTimeInterval(-range.duration)
        let inWindow = samples.filter { $0.date >= start && $0.date <= windowEnd }
        return downsampled(inWindow, bucket: range.duration / Double(BatteryChartRange.maximumPoints))
    }

    static func downsampled(_ samples: [BatteryHistorySample], bucket: TimeInterval) -> [BatteryHistorySample] {
        guard samples.count > BatteryChartRange.maximumPoints, bucket > 0 else { return samples }

        var kept: [BatteryHistorySample] = []
        for (index, sample) in samples.enumerated() {
            guard index + 1 < samples.count else {
                kept.append(sample)
                continue
            }
            let next = samples[index + 1]
            let closesBucket = Int(sample.date.timeIntervalSinceReferenceDate / bucket)
                != Int(next.date.timeIntervalSinceReferenceDate / bucket)
            let closesState = next.isCharging != sample.isCharging || next.onAdapter != sample.onAdapter
            if closesBucket || closesState {
                kept.append(sample)
            }
        }
        return kept
    }

    static func tickDates(range: BatteryChartRange, start: Date, end: Date, calendar: Calendar = .current) -> [Date] {
        let unit = range.tickUnit
        let edgeClearance = range.duration * edgeClearanceFraction
        let boundary = unit == .minute ? DateComponents(second: 0) : DateComponents(minute: 0, second: 0)
        var ticks: [Date] = []
        calendar.enumerateDates(startingAfter: start.addingTimeInterval(-1), matching: boundary, matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date <= end else {
                stop = true
                return
            }
            if calendar.component(unit, from: date) % range.tickStep == 0, end.timeIntervalSince(date) >= edgeClearance {
                ticks.append(date)
            }
        }
        return ticks
    }

    static func windowEnd(for date: Date, calendar: Calendar = .current) -> Date {
        let minute = calendar.dateInterval(of: .minute, for: date)
        return minute?.end ?? date
    }
}
