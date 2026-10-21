import Foundation
import WattyCore

final class DemoTelemetry: TelemetryProviding {
    private let scenario: DemoScenario
    private let now: () -> Date
    private let logger = AppLog.logger("demo")
    private let lock = NSLock()
    private var powerMode = PowerMode.automatic

    init(scenario: DemoScenario, now: @escaping () -> Date = Date.init) {
        self.scenario = scenario
        self.now = now
    }

    func fetchSnapshot(depth: SnapshotDepth, forceDetails: Bool) async -> BatterySnapshot {
        DemoSnapshot.make(for: scenario, at: now(), powerMode: currentPowerMode)
    }

    func fetchSystemStats() async -> SystemStats {
        DemoStats.current(for: scenario, at: now())
    }

    func fetchEnergySample() async -> EnergySample {
        DemoEnergy.sample(for: scenario, at: now())
    }

    func setPowerMode(_ mode: PowerMode) async -> ServiceActionResult {
        remember(mode)
        return ServiceActionResult(reason: .applied(mode), resultingMode: mode)
    }

    func openBatterySettings() {
        logger.info("demo mode does not open System Settings")
    }

    private var currentPowerMode: PowerMode {
        lock.lock()
        defer { lock.unlock() }
        return powerMode
    }

    private func remember(_ mode: PowerMode) {
        lock.lock()
        defer { lock.unlock() }
        powerMode = mode
    }
}
