import Foundation

struct BatteryServiceDependencies {
    var runner: CommandRunning
    var readPowerSource: () -> PowerSourceReadResult
    var readSmartBattery: () -> SmartBatteryReadResult
    var now: () -> Date

    static let live = BatteryServiceDependencies(
        runner: ProcessRunner(),
        readPowerSource: PowerSourceReader.readResult,
        readSmartBattery: SmartBatteryReader.read,
        now: Date.init
    )
}
