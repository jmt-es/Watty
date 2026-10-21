import Foundation
import IOKit.ps

public struct PowerSourceInfo: Equatable {
    public var level: Int?
    public var isCharging: Bool?
    public var isCharged: Bool?
    public var isFinishingCharge: Bool?
    public var externalPower: Bool?
    public var timeToFullMinutes: Int?
    public var timeToEmptyMinutes: Int?
    public var lowPowerModeActive: Bool?

    public init(
        level: Int? = nil,
        isCharging: Bool? = nil,
        isCharged: Bool? = nil,
        isFinishingCharge: Bool? = nil,
        externalPower: Bool? = nil,
        timeToFullMinutes: Int? = nil,
        timeToEmptyMinutes: Int? = nil,
        lowPowerModeActive: Bool? = nil
    ) {
        self.level = level
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.isFinishingCharge = isFinishingCharge
        self.externalPower = externalPower
        self.timeToFullMinutes = timeToFullMinutes
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.lowPowerModeActive = lowPowerModeActive
    }
}

public enum PowerSourceReadResult: Equatable {
    case internalBattery(PowerSourceInfo)
    case noInternalBattery
    case unavailable

    public var internalBattery: PowerSourceInfo? {
        if case .internalBattery(let info) = self { return info }
        return nil
    }
}

public enum PowerSourceReader {
    static let lowPowerModeKey = "LPM Active"

    public static func read() -> PowerSourceInfo? {
        readResult().internalBattery
    }

    public static func readResult() -> PowerSourceReadResult {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .unavailable }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .noInternalBattery
        }
        let providingType = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return select(descriptions: descriptions, providingType: providingType)
    }

    static func select(descriptions: [[String: Any]], providingType: String?) -> PowerSourceReadResult {
        for description in descriptions {
            let type = description[kIOPSTypeKey] as? String
            guard type == nil || type == kIOPSInternalBatteryType else { continue }
            return .internalBattery(parse(description: description, providingType: providingType))
        }
        return .noInternalBattery
    }

    public static func parse(description: [String: Any], providingType: String?) -> PowerSourceInfo {
        let current = intValue(description[kIOPSCurrentCapacityKey])
        let maximum = intValue(description[kIOPSMaxCapacityKey])
        var level: Int?
        if let current, let maximum, maximum > 0 {
            level = Int((Double(current) / Double(maximum) * 100.0).rounded())
        }

        let state = description[kIOPSPowerSourceStateKey] as? String
        let externalPower: Bool?
        if let state {
            externalPower = state == kIOPSACPowerValue
        } else if let providingType {
            externalPower = providingType == kIOPSACPowerValue
        } else {
            externalPower = nil
        }

        return PowerSourceInfo(
            level: level.map { max(0, min(100, $0)) },
            isCharging: boolValue(description[kIOPSIsChargingKey]),
            isCharged: boolValue(description[kIOPSIsChargedKey]),
            isFinishingCharge: boolValue(description[kIOPSIsFinishingChargeKey]),
            externalPower: externalPower,
            timeToFullMinutes: knownMinutes(description[kIOPSTimeToFullChargeKey]),
            timeToEmptyMinutes: knownMinutes(description[kIOPSTimeToEmptyKey]),
            lowPowerModeActive: boolValue(description[lowPowerModeKey])
        )
    }

    private static func knownMinutes(_ value: Any?) -> Int? {
        guard let minutes = intValue(value), minutes > 0 else { return nil }
        return minutes
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }
}
