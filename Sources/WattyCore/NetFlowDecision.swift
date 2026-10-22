import Foundation

struct NetFlowEvidence: Equatable, Sendable {
    let averageWatts: Double?
    let trend: LevelTrend?
}

enum NetFlowDecision {
    static func flow(onAdapter: Bool, reportsCharging: Bool, evidence: NetFlowEvidence, previous: NetFlow?) -> NetFlow? {
        guard onAdapter else { return .draining }
        if let watts = evidence.averageWatts {
            return flow(fromPower: watts, trend: evidence.trend, reportsCharging: reportsCharging, previous: previous)
        }
        return flow(fromTrend: evidence.trend, reportsCharging: reportsCharging, previous: previous)
    }

    private static func flow(fromPower watts: Double, trend: LevelTrend?, reportsCharging: Bool, previous: NetFlow?) -> NetFlow {
        if isDraining(watts, trend: trend, previous: previous) { return .draining }
        guard reportsCharging else { return .holding }
        let threshold = previous == .charging ? NetFlowRules.Power.chargingExitWatts : NetFlowRules.Power.chargingEnterWatts
        return watts >= threshold ? .charging : .holding
    }

    private static func isDraining(_ watts: Double, trend: LevelTrend?, previous: NetFlow?) -> Bool {
        if previous == .draining { return watts <= NetFlowRules.Power.drainingExitWatts }
        guard watts <= NetFlowRules.Power.drainingEnterWatts else { return false }
        let contradictedByLevel = trend?.direction == .rising && watts > NetFlowRules.Power.strongDrainingWatts
        return !contradictedByLevel
    }

    private static func flow(fromTrend trend: LevelTrend?, reportsCharging: Bool, previous: NetFlow?) -> NetFlow? {
        if let trend {
            if trend.direction == .falling || (previous == .draining && trend.isStillFalling) { return .draining }
            if trend.direction == .rising { return reportsCharging ? .charging : .holding }
        }
        return reportsCharging ? nil : .holding
    }
}
