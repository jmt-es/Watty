import Foundation
import WattyCore

enum DemoSnapshot {
    static let readDuration: TimeInterval = 0.014
    static let adapterRatedWatts = 70
    static let adapterDescription = "pd charger"
    static let cycleCount = 142
    static let maximumCapacityPercent = 94
    static let condition = "Normal"

    static let chargingLevel = 76
    static let chargingMinutesToFull = 48
    static let onBatteryLevel = 58
    static let onBatteryMinutesLeft = 252
    static let drainingLevel = 18
    static let drainingMinutesToFull = 579
    static let drainingAdapterRatedWatts = 20

    private static let allPowerModes = PowerModeSupport(
        unifiedKeyAvailable: true,
        supportsLowPower: true,
        supportsHighPower: true
    )

    static func make(for scenario: DemoScenario, at date: Date, powerMode: PowerMode = .automatic) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.lastUpdated = date
        snapshot.readDuration = readDuration
        snapshot.powerMode = powerMode
        snapshot.lowPowerModeActive = powerMode == .lowPower
        snapshot.powerModeSupport = allPowerModes

        switch scenario {
        case .charging: configureCharging(&snapshot)
        case .battery: configureOnBattery(&snapshot)
        case .draining: configureDraining(&snapshot)
        case .desktop: configureDesktop(&snapshot)
        }
        return snapshot
    }

    private static func configureBatteryHealth(_ snapshot: inout BatterySnapshot) {
        snapshot.cycleCount = cycleCount
        snapshot.maximumCapacityPercent = maximumCapacityPercent
        snapshot.condition = condition
    }

    private static func configureCharging(_ snapshot: inout BatterySnapshot) {
        configureBatteryHealth(&snapshot)
        snapshot.level = chargingLevel
        snapshot.isCharging = true
        snapshot.powerSource = .adapter
        snapshot.timeToFullMinutes = chargingMinutesToFull
        snapshot.voltageVolts = 12.61
        snapshot.amperageAmps = 1.57
        snapshot.batteryPowerWatts = 19.8
        snapshot.systemPowerWatts = 42.5
        snapshot.systemLoadWatts = 21.3
        snapshot.adapterRatedWatts = adapterRatedWatts
        snapshot.adapterDescription = adapterDescription
        snapshot.temperatureCelsius = 31.4
    }

    private static func configureOnBattery(_ snapshot: inout BatterySnapshot) {
        configureBatteryHealth(&snapshot)
        snapshot.level = onBatteryLevel
        snapshot.powerSource = .battery
        snapshot.timeToEmptyMinutes = onBatteryMinutesLeft
        snapshot.voltageVolts = 12.13
        snapshot.amperageAmps = -0.75
        snapshot.batteryPowerWatts = -9.1
        snapshot.systemPowerWatts = 0
        snapshot.systemLoadWatts = 9.1
        snapshot.temperatureCelsius = 29.6
    }

    private static func configureDraining(_ snapshot: inout BatterySnapshot) {
        configureBatteryHealth(&snapshot)
        snapshot.level = drainingLevel
        snapshot.isCharging = true
        snapshot.powerSource = .adapter
        snapshot.timeToFullMinutes = drainingMinutesToFull
        snapshot.voltageVolts = 11.42
        snapshot.amperageAmps = -1.6
        snapshot.batteryPowerWatts = -18.3
        snapshot.systemPowerWatts = 19.7
        snapshot.systemLoadWatts = 38.0
        snapshot.adapterRatedWatts = drainingAdapterRatedWatts
        snapshot.adapterDescription = adapterDescription
        snapshot.temperatureCelsius = 38.2
    }

    private static func configureDesktop(_ snapshot: inout BatterySnapshot) {
        snapshot.hasBattery = false
        snapshot.level = 0
        snapshot.powerSource = .adapter
    }
}
