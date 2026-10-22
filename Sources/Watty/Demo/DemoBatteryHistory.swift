import Foundation
import WattyCore

enum DemoBatteryHistory {
    private enum Phase: Equatable {
        case discharging
        case charging
        case pluggedIn
        case draining
    }

    private struct Segment {
        let phase: Phase
        let startMinutesAgo: Int
        let startLevel: Double
        let endMinutesAgo: Int
        let endLevel: Double

        var durationMinutes: Int {
            startMinutesAgo - endMinutesAgo
        }
    }

    private static let secondsPerMinute = 60.0
    private static let seededReadingMinutes = 6

    static let coveredMinutes = Int(BatteryHistory.retention / secondsPerMinute) - 1

    private enum Usage {
        static let minutesPerBurst = 100.0
        static let dischargeSwing = 0.8
        static let chargeSwing = 0.15
    }

    private static func segments(for scenario: DemoScenario) -> [Segment] {
        switch scenario {
        case .charging:
            return [
                Segment(phase: .discharging, startMinutesAgo: 1439, startLevel: 66, endMinutesAgo: 1330, endLevel: 38),
                Segment(phase: .charging, startMinutesAgo: 1330, startLevel: 38, endMinutesAgo: 1285, endLevel: 80),
                Segment(phase: .charging, startMinutesAgo: 1285, startLevel: 80, endMinutesAgo: 1240, endLevel: 100),
                Segment(phase: .pluggedIn, startMinutesAgo: 1240, startLevel: 100, endMinutesAgo: 740, endLevel: 100),
                Segment(phase: .discharging, startMinutesAgo: 740, startLevel: 100, endMinutesAgo: 95, endLevel: 29),
                Segment(phase: .charging, startMinutesAgo: 95, startLevel: 29, endMinutesAgo: 0, endLevel: Double(DemoSnapshot.chargingLevel))
            ]
        case .battery:
            return [
                Segment(phase: .discharging, startMinutesAgo: 1439, startLevel: 62, endMinutesAgo: 1320, endLevel: 34),
                Segment(phase: .charging, startMinutesAgo: 1320, startLevel: 34, endMinutesAgo: 1275, endLevel: 80),
                Segment(phase: .charging, startMinutesAgo: 1275, startLevel: 80, endMinutesAgo: 1230, endLevel: 100),
                Segment(phase: .pluggedIn, startMinutesAgo: 1230, startLevel: 100, endMinutesAgo: 280, endLevel: 100),
                Segment(phase: .discharging, startMinutesAgo: 280, startLevel: 100, endMinutesAgo: 0, endLevel: Double(DemoSnapshot.onBatteryLevel))
            ]
        case .draining:
            return [
                Segment(phase: .discharging, startMinutesAgo: 1439, startLevel: 66, endMinutesAgo: 1330, endLevel: 38),
                Segment(phase: .charging, startMinutesAgo: 1330, startLevel: 38, endMinutesAgo: 1285, endLevel: 80),
                Segment(phase: .charging, startMinutesAgo: 1285, startLevel: 80, endMinutesAgo: 1240, endLevel: 100),
                Segment(phase: .pluggedIn, startMinutesAgo: 1240, startLevel: 100, endMinutesAgo: 540, endLevel: 100),
                Segment(phase: .discharging, startMinutesAgo: 540, startLevel: 100, endMinutesAgo: 65, endLevel: 51),
                Segment(phase: .draining, startMinutesAgo: 65, startLevel: 51, endMinutesAgo: 0, endLevel: Double(DemoSnapshot.drainingLevel))
            ]
        case .desktop:
            return []
        }
    }

    static func samples(for scenario: DemoScenario, endingAt date: Date) -> [BatteryHistorySample] {
        let anchor = Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down))
        let segments = segments(for: scenario)

        return segments.enumerated().flatMap { index, segment -> [BatteryHistorySample] in
            let isLast = index == segments.count - 1
            let lastMinute = isLast ? segment.endMinutesAgo : segment.endMinutesAgo + 1
            return stride(from: segment.startMinutesAgo, through: lastMinute, by: -1).map { minutesAgo in
                BatteryHistorySample(
                    date: anchor.addingTimeInterval(-Double(minutesAgo) * secondsPerMinute),
                    level: Int(level(of: segment, atMinutesAgo: minutesAgo).rounded()),
                    isCharging: segment.phase == .charging || segment.phase == .draining,
                    onAdapter: segment.phase != .discharging
                )
            }
        }
    }

    static func netFlowReadings(for scenario: DemoScenario, endingAt date: Date) -> [NetFlowReading] {
        let batteryWatts = DemoSnapshot.make(for: scenario, at: date).batteryPowerWatts
        return samples(for: scenario, endingAt: date).suffix(seededReadingMinutes).map { sample in
            NetFlowReading(
                date: sample.date,
                batteryWatts: batteryWatts,
                level: sample.level,
                onAdapter: sample.onAdapter,
                reportsCharging: sample.isCharging
            )
        }
    }

    static func makeStore(for scenario: DemoScenario, endingAt date: Date) -> BatteryHistoryStore {
        let store = BatteryHistoryStore(fileURL: nonexistentFileURL(), writesEnabled: false)
        for sample in samples(for: scenario, endingAt: date) {
            store.record(level: sample.level, isCharging: sample.isCharging, onAdapter: sample.onAdapter, at: sample.date)
        }
        return store
    }

    private static func level(of segment: Segment, atMinutesAgo minutesAgo: Int) -> Double {
        guard segment.durationMinutes > 0 else { return segment.endLevel }
        let progress = Double(segment.startMinutesAgo - minutesAgo) / Double(segment.durationMinutes)
        let paced = pacedProgress(progress, in: segment)
        return segment.startLevel + (segment.endLevel - segment.startLevel) * paced
    }

    private static func pacedProgress(_ progress: Double, in segment: Segment) -> Double {
        let swing: Double
        switch segment.phase {
        case .pluggedIn: return progress
        case .discharging, .draining: swing = Usage.dischargeSwing
        case .charging: swing = Usage.chargeSwing
        }
        let bursts = max(1, (Double(segment.durationMinutes) / Usage.minutesPerBurst).rounded())
        let angle = 2 * Double.pi * bursts * progress
        return progress + swing * sin(angle) / (2 * Double.pi * bursts)
    }

    private static func nonexistentFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("watty-demo-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(BatteryHistoryStore.fileName)
    }
}
