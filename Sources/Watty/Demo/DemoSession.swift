import Foundation

@MainActor
enum DemoSession {
    static func makeModel(for scenario: DemoScenario, startedAt: Date = Date()) -> BatteryModel {
        DemoPreferences.apply()
        return BatteryModel(
            service: DemoTelemetry(scenario: scenario),
            historyStore: DemoBatteryHistory.makeStore(for: scenario, endingAt: startedAt),
            seededStatsHistory: DemoStats.history(for: scenario, endingAt: startedAt),
            observesPowerEvents: false
        )
    }
}
