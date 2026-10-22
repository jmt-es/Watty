import Foundation

enum BatteryRegistryKey {
    static let voltage = "Voltage"
    static let rawBatteryVoltage = "AppleRawBatteryVoltage"
    static let instantAmperage = "InstantAmperage"
    static let amperage = "Amperage"
    static let batteryPower = "BatteryPower"
    static let accumulatedBatteryPower = "AccumulatedBatteryPower"
    static let batteryPowerAccumulatorCount = "BatteryPowerAccumulatorCount"
    static let accumulatedBatteryDischarge = "AccumulatedBatteryDischarge"
    static let batteryDischargeAccumulatorCount = "BatteryDischargeAccumulatorCount"
    static let systemPowerIn = "SystemPowerIn"
    static let systemLoad = "SystemLoad"
    static let powerTelemetryData = "PowerTelemetryData"
    static let temperature = "Temperature"
    static let rawMaxCapacity = "AppleRawMaxCapacity"
    static let designCapacity = "DesignCapacity"
    static let maxCapacity = "MaxCapacity"
    static let currentCapacity = "CurrentCapacity"
    static let adapterDetails = "AdapterDetails"
    static let rawAdapterDetails = "AppleRawAdapterDetails"
    static let adapterWatts = "Watts"
    static let adapterDescription = "Description"
    static let cycleCount = "CycleCount"
    static let externalConnected = "ExternalConnected"
    static let isCharging = "IsCharging"
    static let fullyCharged = "FullyCharged"
    static let averageTimeToFull = "AvgTimeToFull"
    static let averageTimeToEmpty = "AvgTimeToEmpty"
}

struct BatteryRegistryValues: Equatable {
    var voltageMilliVolts: Int64?
    var amperageMilliAmps: Int64?
    var telemetryBatteryPowerMilliWatts: Int64?
    var accumulatedChargeMilliWatts: Int64?
    var accumulatedChargeTicks: Int64?
    var accumulatedDischargeMilliWatts: Int64?
    var accumulatedDischargeTicks: Int64?
    var systemPowerInMilliWatts: Int64?
    var systemLoadMilliWatts: Int64?
    var rawTemperature: Int64?
    var rawMaxCapacity: Int64?
    var designCapacity: Int64?
    var maxCapacity: Int64?
    var currentCapacity: Int64?
    var adapterWatts: Int64?
    var adapterDescription: String?
    var cycleCount: Int64?
    var externalConnected: Bool?
    var isCharging: Bool?
    var isFullyCharged: Bool?
    var averageMinutesToFull: Int64?
    var averageMinutesToEmpty: Int64?
}

extension IoregBatteryInfo {
    static let milliUnitsPerUnit = 1000.0
    static let maximumPlausibleBatteryWatts = 250.0
    static let centidegreeThreshold = 1000.0
    static let centidegreesPerDegree = 100.0

    init(_ values: BatteryRegistryValues) {
        let voltage = values.voltageMilliVolts.map { Double($0) / Self.milliUnitsPerUnit }
        let amperage = values.amperageMilliAmps.map { Double($0) / Self.milliUnitsPerUnit }

        let telemetryBatteryPower = values.telemetryBatteryPowerMilliWatts
            .map { Double($0) / Self.milliUnitsPerUnit }
            .flatMap(Self.plausibleBatteryPower)
        var calculatedBatteryPower: Double?
        if let voltage, let amperage {
            calculatedBatteryPower = Self.plausibleBatteryPower(voltage * amperage)
        }

        var maximumCapacityPercent: Int?
        if let rawMaxCapacity = values.rawMaxCapacity, let designCapacity = values.designCapacity, designCapacity > 0 {
            maximumCapacityPercent = Self.roundedPercent(Double(rawMaxCapacity) / Double(designCapacity) * 100.0)
        } else if let maxCapacity = values.maxCapacity, maxCapacity <= 100 {
            maximumCapacityPercent = Int(maxCapacity)
        }

        var currentCapacityPercent: Int?
        if let currentCapacity = values.currentCapacity, let maxCapacity = values.maxCapacity, maxCapacity > 0 {
            currentCapacityPercent = Self.roundedPercent(Double(currentCapacity) / Double(maxCapacity) * 100.0)
        }

        self.init(
            voltageVolts: voltage,
            amperageAmps: amperage,
            batteryPowerWatts: calculatedBatteryPower ?? telemetryBatteryPower,
            powerAccumulation: Self.powerAccumulation(from: values),
            systemPowerWatts: values.systemPowerInMilliWatts.map { Double($0) / Self.milliUnitsPerUnit },
            systemLoadWatts: values.systemLoadMilliWatts.map { Double($0) / Self.milliUnitsPerUnit },
            adapterRatedWatts: values.adapterWatts.map(Int.init),
            adapterDescription: values.adapterDescription,
            cycleCount: values.cycleCount.map(Int.init),
            temperatureCelsius: values.rawTemperature.map { raw in
                let value = Double(raw)
                return value > Self.centidegreeThreshold ? value / Self.centidegreesPerDegree : value
            },
            externalConnected: values.externalConnected,
            isCharging: values.isCharging,
            isFullyCharged: values.isFullyCharged,
            maximumCapacityPercent: maximumCapacityPercent,
            currentCapacityPercent: currentCapacityPercent,
            timeToFullMinutes: Self.knownMinutes(values.averageMinutesToFull),
            timeToEmptyMinutes: Self.knownMinutes(values.averageMinutesToEmpty)
        )
    }

    private static func powerAccumulation(from values: BatteryRegistryValues) -> PowerAccumulation? {
        guard let charge = values.accumulatedChargeMilliWatts, let chargeTicks = values.accumulatedChargeTicks,
              let discharge = values.accumulatedDischargeMilliWatts, let dischargeTicks = values.accumulatedDischargeTicks else {
            return nil
        }
        let (milliwattTicks, powerOverflowed) = charge.addingReportingOverflow(discharge)
        let (ticks, ticksOverflowed) = chargeTicks.addingReportingOverflow(dischargeTicks)
        guard !powerOverflowed, !ticksOverflowed, ticks >= 0 else { return nil }
        return PowerAccumulation(milliwattTicks: milliwattTicks, ticks: ticks)
    }

    private static func plausibleBatteryPower(_ watts: Double) -> Double? {
        abs(watts) <= maximumPlausibleBatteryWatts ? watts : nil
    }

    private static func roundedPercent(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
    }

    private static func knownMinutes(_ value: Int64?) -> Int? {
        guard let value, value > 0, value < TelemetryParsers.unknownIoregMinutes else { return nil }
        return Int(value)
    }
}

extension TelemetryParsers {
    public static func parseSmartBatteryProperties(_ properties: [String: Any]) -> IoregBatteryInfo {
        let registry = RegistryProperties(properties)
        let adapter = adapterDetails(in: registry)

        let values = BatteryRegistryValues(
            voltageMilliVolts: registry.integer(BatteryRegistryKey.voltage)
                ?? registry.integer(BatteryRegistryKey.rawBatteryVoltage),
            amperageMilliAmps: registry.integer(BatteryRegistryKey.instantAmperage)
                ?? registry.integer(BatteryRegistryKey.amperage),
            telemetryBatteryPowerMilliWatts: registry.integer(
                BatteryRegistryKey.batteryPower,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            accumulatedChargeMilliWatts: registry.integer(
                BatteryRegistryKey.accumulatedBatteryPower,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            accumulatedChargeTicks: registry.integer(
                BatteryRegistryKey.batteryPowerAccumulatorCount,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            accumulatedDischargeMilliWatts: registry.integer(
                BatteryRegistryKey.accumulatedBatteryDischarge,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            accumulatedDischargeTicks: registry.integer(
                BatteryRegistryKey.batteryDischargeAccumulatorCount,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            systemPowerInMilliWatts: registry.integer(
                BatteryRegistryKey.systemPowerIn,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            systemLoadMilliWatts: registry.integer(
                BatteryRegistryKey.systemLoad,
                preferring: BatteryRegistryKey.powerTelemetryData
            ),
            rawTemperature: registry.integer(BatteryRegistryKey.temperature),
            rawMaxCapacity: registry.integer(BatteryRegistryKey.rawMaxCapacity),
            designCapacity: registry.integer(BatteryRegistryKey.designCapacity),
            maxCapacity: registry.integer(BatteryRegistryKey.maxCapacity),
            currentCapacity: registry.integer(BatteryRegistryKey.currentCapacity),
            adapterWatts: adapter?.integer(BatteryRegistryKey.adapterWatts),
            adapterDescription: adapter?.string(BatteryRegistryKey.adapterDescription),
            cycleCount: registry.integer(BatteryRegistryKey.cycleCount),
            externalConnected: registry.bool(BatteryRegistryKey.externalConnected),
            isCharging: registry.bool(BatteryRegistryKey.isCharging),
            isFullyCharged: registry.bool(BatteryRegistryKey.fullyCharged),
            averageMinutesToFull: registry.integer(BatteryRegistryKey.averageTimeToFull),
            averageMinutesToEmpty: registry.integer(BatteryRegistryKey.averageTimeToEmpty)
        )
        return IoregBatteryInfo(values)
    }

    private static func adapterDetails(in registry: RegistryProperties) -> RegistryProperties? {
        let candidates = (
            registry.dictionaries(for: BatteryRegistryKey.adapterDetails)
                + registry.dictionaries(for: BatteryRegistryKey.rawAdapterDetails)
        ).map(RegistryProperties.init)
        return candidates.first { $0.integer(BatteryRegistryKey.adapterWatts) != nil } ?? candidates.first
    }
}
