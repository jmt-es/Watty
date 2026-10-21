import Foundation

public protocol TelemetryProviding {
    func fetchSnapshot(depth: SnapshotDepth, forceDetails: Bool) async -> BatterySnapshot
    func fetchSystemStats() async -> SystemStats
    func fetchEnergySample() async -> EnergySample
    func setPowerMode(_ mode: PowerMode) async -> ServiceActionResult
    func openBatterySettings()
}
