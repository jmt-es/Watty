import Foundation

public struct NetFlowReading: Equatable, Sendable {
    public let date: Date
    public let batteryWatts: Double?
    public let powerAccumulation: PowerAccumulation?
    public let level: Int
    public let onAdapter: Bool
    public let reportsCharging: Bool

    public init(
        date: Date,
        batteryWatts: Double?,
        powerAccumulation: PowerAccumulation? = nil,
        level: Int,
        onAdapter: Bool,
        reportsCharging: Bool
    ) {
        self.date = date
        self.batteryWatts = batteryWatts
        self.powerAccumulation = powerAccumulation
        self.level = level
        self.onAdapter = onAdapter
        self.reportsCharging = reportsCharging
    }

    public init?(snapshot: BatterySnapshot) {
        guard snapshot.hasBattery, !snapshot.isEmpty else { return nil }
        self.init(
            date: snapshot.lastUpdated,
            batteryWatts: snapshot.batteryPowerWatts,
            powerAccumulation: snapshot.powerAccumulation,
            level: snapshot.level,
            onAdapter: snapshot.powerSource == .adapter,
            reportsCharging: snapshot.isCharging
        )
    }
}
