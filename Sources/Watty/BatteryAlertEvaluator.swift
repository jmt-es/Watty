import Foundation
import WattyCore

enum BatteryAlertKind: CaseIterable, Hashable {
    case lowBattery
    case chargeLimit
    case fullyCharged
}

struct BatteryAlert: Equatable {
    let kind: BatteryAlertKind
    let level: Int
}

struct BatteryAlertConfiguration: Equatable {
    var lowBatteryEnabled: Bool
    var lowBatteryLevel: Int
    var chargeLimitEnabled: Bool
    var chargeLimitLevel: Int
    var fullyChargedEnabled: Bool
}

struct BatteryAlertEvaluator {
    static let rearmMargin = 2
    // Wider than the other margins so small dips while held on the adapter don't announce a new full charge.
    static let fullyChargedRearmMargin = 5

    private enum Phase {
        case armed
        case fired
    }

    private struct Tracking {
        var phase: Phase
        var threshold: Int
    }

    private struct Check {
        let kind: BatteryAlertKind
        let enabled: Bool
        let threshold: Int
        let isActive: Bool
        let canRearm: Bool
    }

    private var tracking: [BatteryAlertKind: Tracking] = [:]

    mutating func evaluate(level: Int, chargeState: ChargeState, configuration: BatteryAlertConfiguration) -> [BatteryAlert] {
        checks(level: level, chargeState: chargeState, configuration: configuration).compactMap { check in
            advance(check) ? BatteryAlert(kind: check.kind, level: level) : nil
        }
    }

    private func checks(level: Int, chargeState: ChargeState, configuration: BatteryAlertConfiguration) -> [Check] {
        let onBattery = chargeState == .onBattery
        let pluggedAndFilling = chargeState == .charging || chargeState == .charged

        return [
            Check(
                kind: .lowBattery,
                enabled: configuration.lowBatteryEnabled,
                threshold: configuration.lowBatteryLevel,
                isActive: onBattery && level <= configuration.lowBatteryLevel,
                canRearm: !onBattery || level >= configuration.lowBatteryLevel + Self.rearmMargin
            ),
            Check(
                kind: .chargeLimit,
                enabled: configuration.chargeLimitEnabled,
                threshold: configuration.chargeLimitLevel,
                isActive: pluggedAndFilling && level >= configuration.chargeLimitLevel,
                canRearm: onBattery || level <= configuration.chargeLimitLevel - Self.rearmMargin
            ),
            Check(
                kind: .fullyCharged,
                enabled: configuration.fullyChargedEnabled,
                threshold: 0,
                isActive: chargeState == .charged,
                canRearm: onBattery || level <= 100 - Self.fullyChargedRearmMargin
            )
        ]
    }

    private mutating func advance(_ check: Check) -> Bool {
        guard check.enabled else {
            tracking[check.kind] = nil
            return false
        }

        guard var current = tracking[check.kind], current.threshold == check.threshold else {
            tracking[check.kind] = Tracking(phase: check.isActive ? .fired : .armed, threshold: check.threshold)
            return false
        }

        switch current.phase {
        case .armed where check.isActive:
            current.phase = .fired
            tracking[check.kind] = current
            return true
        case .fired where check.canRearm && !check.isActive:
            current.phase = .armed
            tracking[check.kind] = current
            return false
        default:
            return false
        }
    }
}
