import AppKit
import Foundation

public enum PowerSource: String, Equatable {
    case battery = "Battery"
    case adapter = "Power Adapter"
    case unknown = "Unknown"
}

public enum PowerMode: Int, CaseIterable, Identifiable, Equatable {
    case automatic = 0
    case lowPower = 1
    case highPower = 2

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Auto"
        case .lowPower: return "Low"
        case .highPower: return "High"
        }
    }

    public var longTitle: String {
        switch self {
        case .automatic: return "Automatic"
        case .lowPower: return "Low Power"
        case .highPower: return "High Power"
        }
    }

    public var unifiedCommand: String {
        "/usr/bin/pmset -a powermode \(rawValue)"
    }

    public var legacyCommands: [String] {
        switch self {
        case .automatic:
            return ["/usr/bin/pmset -a lowpowermode 0", "/usr/bin/pmset -a highpowermode 0"]
        case .lowPower:
            return ["/usr/bin/pmset -a highpowermode 0", "/usr/bin/pmset -a lowpowermode 1"]
        case .highPower:
            return ["/usr/bin/pmset -a lowpowermode 0", "/usr/bin/pmset -a highpowermode 1"]
        }
    }

    public func shellScript(support: PowerModeSupport) -> String {
        let legacy = support.supportsHighPower
            ? legacyCommands
            : legacyCommands.filter { !$0.contains("highpowermode") }
        let legacyScript = legacy.joined(separator: " && ")
        guard support.unifiedKeyAvailable else { return legacyScript }
        return "\(unifiedCommand) || (\(legacyScript))"
    }
}

public struct PowerModeSupport: Equatable {
    public var unifiedKeyAvailable: Bool
    public var supportsLowPower: Bool
    public var supportsHighPower: Bool

    public init(unifiedKeyAvailable: Bool, supportsLowPower: Bool, supportsHighPower: Bool) {
        self.unifiedKeyAvailable = unifiedKeyAvailable
        self.supportsLowPower = supportsLowPower
        self.supportsHighPower = supportsHighPower
    }

    public init(capabilities: Set<String>, settings: PmsetSettingsInfo) {
        unifiedKeyAvailable = settings.powerMode != nil
        supportsLowPower = capabilities.contains("lowpowermode")
            || settings.lowPowerMode != nil
            || settings.powerMode != nil
        supportsHighPower = capabilities.contains("highpowermode") || settings.highPowerMode != nil
    }

    public static let unknown = PowerModeSupport(
        unifiedKeyAvailable: false,
        supportsLowPower: true,
        supportsHighPower: true
    )

    public var availableModes: [PowerMode] {
        PowerMode.allCases.filter { mode in
            switch mode {
            case .automatic: return true
            case .lowPower: return supportsLowPower
            case .highPower: return supportsHighPower
            }
        }
    }
}

public enum ChargeState: Equatable {
    case charging
    case charged
    case pluggedInNotCharging
    case onBattery
    case unknown

    public var title: String {
        switch self {
        case .charging: return "Charging"
        case .charged: return "Charged"
        case .pluggedInNotCharging: return "Plugged in, not charging"
        case .onBattery: return "On battery"
        case .unknown: return "Reading battery"
        }
    }
}

public struct BatterySnapshot: Equatable {
    public var hasBattery: Bool
    public var level: Int
    public var isCharging: Bool
    public var isFullyCharged: Bool
    public var isFinishingCharge: Bool
    public var powerSource: PowerSource
    public var timeToFullMinutes: Int?
    public var timeToEmptyMinutes: Int?
    public var voltageVolts: Double?
    public var amperageAmps: Double?
    public var batteryPowerWatts: Double?
    public var systemPowerWatts: Double?
    public var systemLoadWatts: Double?
    public var adapterRatedWatts: Int?
    public var adapterDescription: String?
    public var cycleCount: Int?
    public var condition: String?
    public var maximumCapacityPercent: Int?
    public var temperatureCelsius: Double?
    public var powerMode: PowerMode?
    public var lowPowerModeActive: Bool?
    public var powerModeSupport: PowerModeSupport
    public var readDuration: TimeInterval
    public var lastUpdated: Date
    public var warnings: [String]

    public var isEmpty: Bool {
        lastUpdated == Date.distantPast
    }

    public var chargeState: ChargeState {
        if isEmpty { return .unknown }
        if isCharging { return .charging }
        if powerSource == .adapter {
            return isFullyCharged || level >= 100 ? .charged : .pluggedInNotCharging
        }
        return .onBattery
    }

    public var timeRemainingText: String {
        timeRemaining.text
    }

    public static func clockText(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static let empty = BatterySnapshot(
        hasBattery: true,
        level: 0,
        isCharging: false,
        isFullyCharged: false,
        isFinishingCharge: false,
        powerSource: .unknown,
        timeToFullMinutes: nil,
        timeToEmptyMinutes: nil,
        voltageVolts: nil,
        amperageAmps: nil,
        batteryPowerWatts: nil,
        systemPowerWatts: nil,
        systemLoadWatts: nil,
        adapterRatedWatts: nil,
        adapterDescription: nil,
        cycleCount: nil,
        condition: nil,
        maximumCapacityPercent: nil,
        temperatureCelsius: nil,
        powerMode: nil,
        lowPowerModeActive: nil,
        powerModeSupport: .unknown,
        readDuration: 0,
        lastUpdated: Date.distantPast,
        warnings: []
    )
}

public struct EnergyConsumer: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let pid: Int?
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let icon: NSImage?

    public init(
        id: String,
        name: String,
        pid: Int?,
        cpuPercent: Double,
        memoryBytes: UInt64,
        icon: NSImage?
    ) {
        self.id = id
        self.name = name
        self.pid = pid
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.icon = icon
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EnergyConsumer, rhs: EnergyConsumer) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.pid == rhs.pid
            && lhs.cpuPercent == rhs.cpuPercent
            && lhs.memoryBytes == rhs.memoryBytes
    }
}

public struct EnergySample: Equatable {
    public var consumers: [EnergyConsumer]
    public var sampledAt: Date
    public var duration: TimeInterval
    public var failed: Bool
    public var isWarmingUp: Bool

    public init(consumers: [EnergyConsumer], sampledAt: Date, duration: TimeInterval, failed: Bool, isWarmingUp: Bool) {
        self.consumers = consumers
        self.sampledAt = sampledAt
        self.duration = duration
        self.failed = failed
        self.isWarmingUp = isWarmingUp
    }

    public static let empty = EnergySample(consumers: [], sampledAt: Date.distantPast, duration: 0, failed: false, isWarmingUp: true)

    public var isEmpty: Bool {
        sampledAt == Date.distantPast
    }
}
