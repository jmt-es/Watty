import Foundation
import os

public struct PmsetBatteryInfo: Equatable {
    public var level: Int
    public var isCharging: Bool
    public var isFullyCharged: Bool
    public var powerSource: PowerSource
    public var timeRemainingMinutes: Int?
    public var timeRemainingText: String
}

public struct PmsetSettingsInfo: Equatable {
    public var powerMode: Int?
    public var lowPowerMode: Int?
    public var highPowerMode: Int?

    public init(powerMode: Int? = nil, lowPowerMode: Int? = nil, highPowerMode: Int? = nil) {
        self.powerMode = powerMode
        self.lowPowerMode = lowPowerMode
        self.highPowerMode = highPowerMode
    }

    public var unifiedKeyAvailable: Bool {
        powerMode != nil
    }

    public var resolvedMode: PowerMode? {
        if let powerMode {
            return PowerMode(rawValue: powerMode)
        }
        if highPowerMode == 1 { return .highPower }
        if lowPowerMode == 1 { return .lowPower }
        if lowPowerMode != nil || highPowerMode != nil { return .automatic }
        return nil
    }
}

public struct IoregBatteryInfo: Equatable {
    public var voltageVolts: Double?
    public var amperageAmps: Double?
    public var batteryPowerWatts: Double?
    public var systemPowerWatts: Double?
    public var systemLoadWatts: Double?
    public var adapterRatedWatts: Int?
    public var adapterDescription: String?
    public var cycleCount: Int?
    public var temperatureCelsius: Double?
    public var externalConnected: Bool?
    public var isCharging: Bool?
    public var isFullyCharged: Bool?
    public var maximumCapacityPercent: Int?
    public var currentCapacityPercent: Int?
    public var timeToFullMinutes: Int?
    public var timeToEmptyMinutes: Int?
}

public struct SystemProfilerPowerInfo: Equatable {
    public var cycleCount: Int?
    public var condition: String?
    public var maximumCapacityPercent: Int?
    public var adapterRatedWatts: Int?
    public var lowPowerMode: Bool?
    public var highPowerMode: Bool?
}

public struct EnergyIdentity: Equatable {
    public var key: String
    public var name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

public struct ParsedEnergyProcess: Equatable {
    public var key: String
    public var name: String
    public var pids: [Int]
    public var cpuPercent: Double
    public var memoryBytes: UInt64
}

public enum TelemetryParsers {
    static let unknownIoregMinutes = 65535
    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "parsers")

    public static func parsePmsetBattery(_ output: String) -> PmsetBatteryInfo {
        var info = PmsetBatteryInfo(
            level: 0,
            isCharging: false,
            isFullyCharged: false,
            powerSource: .unknown,
            timeRemainingMinutes: nil,
            timeRemainingText: "---"
        )

        for line in output.components(separatedBy: .newlines) {
            if line.contains("Now drawing from") {
                if line.localizedCaseInsensitiveContains("Battery Power") {
                    info.powerSource = .battery
                } else if line.localizedCaseInsensitiveContains("AC Power") {
                    info.powerSource = .adapter
                }
            }

            guard line.contains("InternalBattery") else { continue }

            if let percent = firstMatch(in: line, pattern: #"(\d+)%"#),
               let level = Int(percent) {
                info.level = max(0, min(100, level))
            }

            let lowercased = line.lowercased()
            info.isCharging = lowercased.contains("charging") && !lowercased.contains("discharging")
            info.isFullyCharged = lowercased.contains("charged")

            if let time = firstMatch(in: line, pattern: #"(\d+:\d+)\s+remaining"#) {
                info.timeRemainingText = time
                let parts = time.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2 {
                    info.timeRemainingMinutes = parts[0] * 60 + parts[1]
                }
            } else if lowercased.contains("no estimate") {
                info.timeRemainingText = "No estimate"
            } else if info.isFullyCharged {
                info.timeRemainingText = "Charged"
            }
        }

        return info
    }

    public static func parsePmsetSettings(_ output: String) -> PmsetSettingsInfo {
        let values = lowercaseKeyValues(in: output)
        return PmsetSettingsInfo(
            powerMode: values["powermode"],
            lowPowerMode: values["lowpowermode"],
            highPowerMode: values["highpowermode"]
        )
    }

    public static func parsePmsetCapabilities(_ output: String) -> Set<String> {
        var capabilities: Set<String> = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasSuffix(":") else { continue }
            guard let first = line.first, first.isLowercase else { continue }
            capabilities.insert(line.lowercased())
        }
        return capabilities
    }

    public static func parseIoregBattery(_ output: String) -> IoregBatteryInfo {
        let adapterLine = output
            .components(separatedBy: .newlines)
            .first {
                $0.contains("\"\(BatteryRegistryKey.adapterDetails)\"")
                    || $0.contains("\"\(BatteryRegistryKey.rawAdapterDetails)\"")
            }

        let values = BatteryRegistryValues(
            voltageMilliVolts: signedNumber(forKey: BatteryRegistryKey.voltage, in: output)
                ?? signedNumber(forKey: BatteryRegistryKey.rawBatteryVoltage, in: output),
            amperageMilliAmps: signedNumber(forKey: BatteryRegistryKey.instantAmperage, in: output)
                ?? signedNumber(forKey: BatteryRegistryKey.amperage, in: output),
            telemetryBatteryPowerMilliWatts: signedNumber(forKey: BatteryRegistryKey.batteryPower, in: output),
            systemPowerInMilliWatts: signedNumber(forKey: BatteryRegistryKey.systemPowerIn, in: output),
            systemLoadMilliWatts: signedNumber(forKey: BatteryRegistryKey.systemLoad, in: output),
            rawTemperature: signedNumber(forKey: BatteryRegistryKey.temperature, in: output),
            rawMaxCapacity: signedNumber(forKey: BatteryRegistryKey.rawMaxCapacity, in: output),
            designCapacity: signedNumber(forKey: BatteryRegistryKey.designCapacity, in: output),
            maxCapacity: signedNumber(forKey: BatteryRegistryKey.maxCapacity, in: output),
            currentCapacity: signedNumber(forKey: BatteryRegistryKey.currentCapacity, in: output),
            adapterWatts: adapterLine.flatMap { signedNumber(forKey: BatteryRegistryKey.adapterWatts, in: $0) },
            adapterDescription: firstQuotedValue(forKey: BatteryRegistryKey.adapterDescription, in: adapterLine ?? output),
            cycleCount: signedNumber(forKey: BatteryRegistryKey.cycleCount, in: output),
            externalConnected: boolValue(forKey: BatteryRegistryKey.externalConnected, in: output),
            isCharging: boolValue(forKey: BatteryRegistryKey.isCharging, in: output),
            isFullyCharged: boolValue(forKey: BatteryRegistryKey.fullyCharged, in: output),
            averageMinutesToFull: signedNumber(forKey: BatteryRegistryKey.averageTimeToFull, in: output),
            averageMinutesToEmpty: signedNumber(forKey: BatteryRegistryKey.averageTimeToEmpty, in: output)
        )
        return IoregBatteryInfo(values)
    }

    public static func parseSystemProfilerPower(_ output: String) -> SystemProfilerPowerInfo {
        var info = SystemProfilerPowerInfo()

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Cycle Count:") {
                info.cycleCount = integerAfterColon(in: line)
            } else if line.hasPrefix("Condition:") {
                info.condition = stringAfterColon(in: line)
            } else if line.hasPrefix("Maximum Capacity:") {
                info.maximumCapacityPercent = integerAfterColon(in: line)
            } else if line.hasPrefix("Wattage (W):") {
                info.adapterRatedWatts = integerAfterColon(in: line)
            } else if line.hasPrefix("Low Power Mode:") {
                info.lowPowerMode = line.localizedCaseInsensitiveContains("Yes")
            } else if line.hasPrefix("High Power Mode:") {
                info.highPowerMode = line.localizedCaseInsensitiveContains("Yes")
            }
        }

        return info
    }

    public static func aggregateEnergy(
        _ rows: [ProcessEnergyRow],
        identity: (ProcessEnergyRow) -> EnergyIdentity
    ) -> [ParsedEnergyProcess] {
        var buckets: [String: ParsedEnergyProcess] = [:]

        for row in rows {
            let resolved = identity(row)
            guard !ignoredProcessNames.contains(resolved.name),
                  !resolved.name.hasPrefix("com.apple.") else {
                continue
            }

            if var existing = buckets[resolved.key] {
                existing.cpuPercent += row.cpuPercent
                existing.memoryBytes += row.memoryBytes
                existing.pids.append(row.pid)
                buckets[resolved.key] = existing
            } else {
                buckets[resolved.key] = ParsedEnergyProcess(
                    key: resolved.key,
                    name: resolved.name,
                    pids: [row.pid],
                    cpuPercent: row.cpuPercent,
                    memoryBytes: row.memoryBytes
                )
            }
        }

        return buckets.values.sorted {
            if $0.cpuPercent == $1.cpuPercent {
                return $0.memoryBytes > $1.memoryBytes
            }
            return $0.cpuPercent > $1.cpuPercent
        }
    }

    public static let ignoredProcessNames: Set<String> = [
        "ioreg", "launchd", "logd", "pmset", "system_profiler", "trustd", "Watty"
    ]

    static let helperNameFragments: [String] = [
        " Helper (Renderer)",
        " Helper (GPU)",
        " Helper (Plugin)",
        " Helper",
        " (Renderer)",
        " (GPU)",
        " (Service)",
        " Service"
    ]

    public static func normalizedProcessName(_ command: String) -> String {
        var name = command
        for fragment in helperNameFragments {
            name = name.replacingOccurrences(of: fragment, with: "")
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return command.trimmingCharacters(in: .whitespaces) }

        if name.hasPrefix("MTLCompiler") { return "Metal Compiler" }
        if name.hasPrefix("com.apple.WebKit") { return "Safari Web Content" }
        return name
    }

    private static func lowercaseKeyValues(in output: String) -> [String: Int] {
        var values: [String: Int] = [:]
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let first = line.first, first.isLowercase else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let value = Int(parts[1]) else { continue }
            let key = parts[0].lowercased()
            if values[key] == nil {
                values[key] = value
            }
        }
        return values
    }

    private static func integerAfterColon(in line: String) -> Int? {
        guard let value = stringAfterColon(in: line) else { return nil }
        return Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
    }

    private static func stringAfterColon(in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func boolValue(forKey key: String, in output: String) -> Bool? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""# + escaped + #""\s*=\s*(Yes|No)"#
        guard let value = firstMatch(in: output, pattern: pattern) else { return nil }
        return value == "Yes"
    }

    private static func signedNumber(forKey key: String, in output: String) -> Int64? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let quotedPattern = #"(^|[\s\{,\(])""# + escaped + #""\s*=\s*(-?\d+)"#
        if let value = firstMatch(in: output, pattern: quotedPattern, captureGroup: 2) {
            return signedInteger(from: value)
        }

        let unquotedPattern = #"(^|[\s\{,\(])"# + escaped + #"\s*=\s*(-?\d+)"#
        return firstMatch(in: output, pattern: unquotedPattern, captureGroup: 2).flatMap(signedInteger)
    }

    static func signedInteger(from value: String) -> Int64? {
        if let intValue = Int64(value) {
            return intValue
        }
        if let uintValue = UInt64(value) {
            return Int64(bitPattern: uintValue)
        }
        return nil
    }

    private static func firstQuotedValue(forKey key: String, in output: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        return firstMatch(in: output, pattern: #""# + escaped + #""\s*=\s*"([^"]+)""#)
    }

    private static func firstMatch(in text: String, pattern: String, captureGroup: Int = 1) -> String? {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            logger.error("Invalid regular expression \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > captureGroup,
              let swiftRange = Range(match.range(at: captureGroup), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}
