import Foundation

public enum ReportSchema {
    public static let version = 1
}

public enum ReportChargeState: String, Encodable, Equatable, Sendable {
    case charging
    case charged
    case pluggedInNotCharging = "plugged_in_not_charging"
    case onBattery = "on_battery"

    init?(_ state: ChargeState) {
        switch state {
        case .charging: self = .charging
        case .charged: self = .charged
        case .pluggedInNotCharging: self = .pluggedInNotCharging
        case .onBattery: self = .onBattery
        case .pluggedInDraining, .unknown: return nil
        }
    }
}

public enum ReportNetFlow: String, Encodable, Equatable, Sendable {
    case charging
    case draining
    case holding

    init(_ flow: NetFlow) {
        switch flow {
        case .charging: self = .charging
        case .draining: self = .draining
        case .holding: self = .holding
        }
    }
}

public enum ReportPowerSource: String, Encodable, Equatable, Sendable {
    case battery
    case adapter

    init?(_ source: PowerSource) {
        switch source {
        case .battery: self = .battery
        case .adapter: self = .adapter
        case .unknown: return nil
        }
    }
}

public enum ReportPowerMode: String, Encodable, Equatable, Sendable {
    case automatic
    case lowPower = "low_power"
    case highPower = "high_power"

    init(_ mode: PowerMode) {
        switch mode {
        case .automatic: self = .automatic
        case .lowPower: self = .lowPower
        case .highPower: self = .highPower
        }
    }
}

enum ReportPrecision {
    static let watts = 2
    static let volts = 3
    static let amps = 3
    static let celsius = 1
    static let percent = 1
    static let seconds = 2
}

enum ReportRounding {
    static func rounded(_ value: Double, decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        let result = (value * scale).rounded() / scale
        return result == 0 ? 0 : result
    }

    static func roundedOrNil(_ value: Double?, decimals: Int) -> Double? {
        guard let value, value.isFinite else { return nil }
        return rounded(value, decimals: decimals)
    }
}

enum ReportTimestamp {
    static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        try encode(value, forKey: key)
    }
}

public enum ReportEncoder {
    public static func jsonString<Report: Encodable>(for report: Report) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }
}

public struct StatusReport: Encodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wattyVersion: String
    public let timestamp: String
    public let hasBattery: Bool
    public let battery: BatteryStatus
    public let power: PowerStatus
    public let system: SystemStatus
    public let warnings: [String]

    public init(
        snapshot: BatterySnapshot,
        stats: SystemStats,
        generatedAt: Date,
        wattyVersion: String = WattyVersion.current
    ) {
        schemaVersion = ReportSchema.version
        self.wattyVersion = wattyVersion
        timestamp = ReportTimestamp.string(from: generatedAt)
        hasBattery = snapshot.hasBattery
        battery = BatteryStatus(snapshot)
        power = PowerStatus(snapshot)
        system = SystemStatus(stats)
        warnings = snapshot.warnings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wattyVersion = "watty_version"
        case timestamp
        case hasBattery = "has_battery"
        case battery
        case power
        case system
        case warnings
    }

    public struct BatteryStatus: Encodable, Equatable, Sendable {
        public internal(set) var levelPercent: Int?
        public internal(set) var state: ReportChargeState?
        public internal(set) var netFlow: ReportNetFlow?
        public internal(set) var averagePowerWatts: Double?
        public internal(set) var timeToFullMinutes: Int?
        public internal(set) var timeToEmptyMinutes: Int?
        public internal(set) var powerWatts: Double?
        public internal(set) var voltageVolts: Double?
        public internal(set) var amperageAmps: Double?
        public internal(set) var temperatureCelsius: Double?
        public internal(set) var cycleCount: Int?
        public internal(set) var maximumCapacityPercent: Int?
        public internal(set) var condition: String?

        init(_ snapshot: BatterySnapshot) {
            guard snapshot.hasBattery, !snapshot.isEmpty else { return }
            let state = ReportChargeState(snapshot.reportedChargeState)
            levelPercent = snapshot.level
            self.state = state
            netFlow = snapshot.netFlow.flow.map(ReportNetFlow.init)
            averagePowerWatts = ReportRounding.roundedOrNil(snapshot.netFlow.averageBatteryWatts, decimals: ReportPrecision.watts)
            timeToFullMinutes = state == .charging && !snapshot.isDrainingOnAdapter ? snapshot.timeToFullMinutes : nil
            timeToEmptyMinutes = state == .onBattery ? snapshot.timeToEmptyMinutes : nil
            powerWatts = ReportRounding.roundedOrNil(snapshot.batteryPowerWatts, decimals: ReportPrecision.watts)
            voltageVolts = ReportRounding.roundedOrNil(snapshot.voltageVolts, decimals: ReportPrecision.volts)
            amperageAmps = ReportRounding.roundedOrNil(snapshot.amperageAmps, decimals: ReportPrecision.amps)
            temperatureCelsius = ReportRounding.roundedOrNil(snapshot.temperatureCelsius, decimals: ReportPrecision.celsius)
            cycleCount = snapshot.cycleCount
            maximumCapacityPercent = snapshot.maximumCapacityPercent
            condition = snapshot.condition
        }

        private enum CodingKeys: String, CodingKey {
            case levelPercent = "level_percent"
            case state
            case netFlow = "net_flow"
            case timeToFullMinutes = "time_to_full_minutes"
            case timeToEmptyMinutes = "time_to_empty_minutes"
            case powerWatts = "power_watts"
            case voltageVolts = "voltage_volts"
            case amperageAmps = "amperage_amps"
            case temperatureCelsius = "temperature_celsius"
            case cycleCount = "cycle_count"
            case maximumCapacityPercent = "maximum_capacity_percent"
            case condition
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNullable(levelPercent, forKey: .levelPercent)
            try container.encodeNullable(state, forKey: .state)
            try container.encodeNullable(netFlow, forKey: .netFlow)
            try container.encodeNullable(timeToFullMinutes, forKey: .timeToFullMinutes)
            try container.encodeNullable(timeToEmptyMinutes, forKey: .timeToEmptyMinutes)
            try container.encodeNullable(powerWatts, forKey: .powerWatts)
            try container.encodeNullable(voltageVolts, forKey: .voltageVolts)
            try container.encodeNullable(amperageAmps, forKey: .amperageAmps)
            try container.encodeNullable(temperatureCelsius, forKey: .temperatureCelsius)
            try container.encodeNullable(cycleCount, forKey: .cycleCount)
            try container.encodeNullable(maximumCapacityPercent, forKey: .maximumCapacityPercent)
            try container.encodeNullable(condition, forKey: .condition)
        }
    }

    public struct PowerStatus: Encodable, Equatable, Sendable {
        public internal(set) var source: ReportPowerSource?
        public internal(set) var adapterRatedWatts: Int?
        public internal(set) var systemInputWatts: Double?
        public internal(set) var systemLoadWatts: Double?
        public internal(set) var mode: ReportPowerMode?
        public internal(set) var lowPowerModeActive: Bool?

        init(_ snapshot: BatterySnapshot) {
            let onAdapter = snapshot.powerSource == .adapter
            source = snapshot.hasBattery ? ReportPowerSource(snapshot.powerSource) : nil
            adapterRatedWatts = onAdapter ? snapshot.adapterRatedWatts : nil
            systemInputWatts = ReportRounding.roundedOrNil(snapshot.systemPowerWatts, decimals: ReportPrecision.watts)
            systemLoadWatts = ReportRounding.roundedOrNil(Self.systemLoad(of: snapshot), decimals: ReportPrecision.watts)
            mode = snapshot.powerMode.map(ReportPowerMode.init)
            lowPowerModeActive = snapshot.lowPowerModeActive
        }

        static func systemLoad(of snapshot: BatterySnapshot) -> Double? {
            if let load = snapshot.systemLoadWatts { return load }
            guard let battery = snapshot.batteryPowerWatts else { return nil }
            if snapshot.powerSource == .adapter, let input = snapshot.systemPowerWatts {
                return max(0, input - battery)
            }
            return battery < 0 ? -battery : nil
        }

        private enum CodingKeys: String, CodingKey {
            case source
            case adapterRatedWatts = "adapter_rated_watts"
            case systemInputWatts = "system_input_watts"
            case systemLoadWatts = "system_load_watts"
            case mode
            case lowPowerModeActive = "low_power_mode_active"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNullable(source, forKey: .source)
            try container.encodeNullable(adapterRatedWatts, forKey: .adapterRatedWatts)
            try container.encodeNullable(systemInputWatts, forKey: .systemInputWatts)
            try container.encodeNullable(systemLoadWatts, forKey: .systemLoadWatts)
            try container.encodeNullable(mode, forKey: .mode)
            try container.encodeNullable(lowPowerModeActive, forKey: .lowPowerModeActive)
        }
    }

    public struct SystemStatus: Encodable, Equatable, Sendable {
        public internal(set) var socTemperatureCelsius: Double?
        public internal(set) var cpuPercent: Double?
        public internal(set) var cpuUserPercent: Double?
        public internal(set) var cpuSystemPercent: Double?
        public internal(set) var memoryPercent: Double?
        public internal(set) var memoryUsedBytes: UInt64?
        public internal(set) var memoryTotalBytes: UInt64?
        public internal(set) var swapUsedBytes: UInt64?

        init(_ stats: SystemStats) {
            socTemperatureCelsius = ReportRounding.roundedOrNil(stats.temperature?.socMaxCelsius, decimals: ReportPrecision.celsius)
            if let cpu = stats.cpu {
                cpuPercent = ReportRounding.rounded(cpu.totalPercent, decimals: ReportPrecision.percent)
                cpuUserPercent = ReportRounding.rounded(cpu.userPercent, decimals: ReportPrecision.percent)
                cpuSystemPercent = ReportRounding.rounded(cpu.systemPercent, decimals: ReportPrecision.percent)
            }
            if let memory = stats.memory {
                memoryPercent = ReportRounding.rounded(memory.usedPercent, decimals: ReportPrecision.percent)
                memoryUsedBytes = memory.usedBytes
                memoryTotalBytes = memory.totalBytes
                swapUsedBytes = memory.swapUsedBytes
            }
        }

        private enum CodingKeys: String, CodingKey {
            case socTemperatureCelsius = "soc_temperature_celsius"
            case cpuPercent = "cpu_percent"
            case cpuUserPercent = "cpu_user_percent"
            case cpuSystemPercent = "cpu_system_percent"
            case memoryPercent = "memory_percent"
            case memoryUsedBytes = "memory_used_bytes"
            case memoryTotalBytes = "memory_total_bytes"
            case swapUsedBytes = "swap_used_bytes"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNullable(socTemperatureCelsius, forKey: .socTemperatureCelsius)
            try container.encodeNullable(cpuPercent, forKey: .cpuPercent)
            try container.encodeNullable(cpuUserPercent, forKey: .cpuUserPercent)
            try container.encodeNullable(cpuSystemPercent, forKey: .cpuSystemPercent)
            try container.encodeNullable(memoryPercent, forKey: .memoryPercent)
            try container.encodeNullable(memoryUsedBytes, forKey: .memoryUsedBytes)
            try container.encodeNullable(memoryTotalBytes, forKey: .memoryTotalBytes)
            try container.encodeNullable(swapUsedBytes, forKey: .swapUsedBytes)
        }
    }
}

public struct TopReport: Encodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let wattyVersion: String
    public let timestamp: String
    public let intervalSeconds: Double
    public let consumers: [Consumer]

    public init(
        sample: EnergySample,
        limit: Int,
        intervalSeconds: Double,
        generatedAt: Date,
        wattyVersion: String = WattyVersion.current
    ) {
        schemaVersion = ReportSchema.version
        self.wattyVersion = wattyVersion
        timestamp = ReportTimestamp.string(from: generatedAt)
        self.intervalSeconds = ReportRounding.rounded(intervalSeconds, decimals: ReportPrecision.seconds)
        consumers = sample.consumers
            .sorted(by: Self.isHigherConsumer)
            .prefix(max(0, limit))
            .map(Consumer.init)
    }

    private static func isHigherConsumer(_ lhs: EnergyConsumer, _ rhs: EnergyConsumer) -> Bool {
        if lhs.cpuPercent != rhs.cpuPercent { return lhs.cpuPercent > rhs.cpuPercent }
        if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
        return lhs.name < rhs.name
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case wattyVersion = "watty_version"
        case timestamp
        case intervalSeconds = "interval_seconds"
        case consumers
    }

    public struct Consumer: Encodable, Equatable, Sendable {
        public let name: String
        public let cpuPercent: Double
        public let memoryBytes: UInt64?

        init(_ consumer: EnergyConsumer) {
            name = consumer.name
            cpuPercent = ReportRounding.rounded(consumer.cpuPercent, decimals: ReportPrecision.percent)
            memoryBytes = Self.knownMemory(consumer.memoryBytes)
        }

        // Processes sampled through ps (other users, system daemons) carry no footprint and arrive as 0.
        private static func knownMemory(_ bytes: UInt64) -> UInt64? {
            bytes > 0 ? bytes : nil
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case cpuPercent = "cpu_percent"
            case memoryBytes = "memory_bytes"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(cpuPercent, forKey: .cpuPercent)
            try container.encodeNullable(memoryBytes, forKey: .memoryBytes)
        }
    }
}
