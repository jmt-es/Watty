import Foundation
import WattyCore

enum DemoStats {
    struct Profile {
        let cpu: CPUUsage
        let memory: MemoryUsage
        let socMaxCelsius: Double
        let socAverageCelsius: Double
    }

    static let sensorCount = 6
    static let historyInterval = RefreshCadence.visibleSnapshot

    private static let bytesPerGibibyte = 1_073_741_824.0

    private enum Swing {
        static let cpuShareOfLoad = 0.9
        static let cpuJitterShareOfLoad = 0.12
        static let minimumCPUPercent = 2.0
        static let memoryPercent = 1.4
        static let memoryDriftPercent = 1.0
        static let socCelsius = 2.4
    }

    private enum Seed {
        static let cpu: UInt64 = 11
        static let cpuJitter: UInt64 = 12
        static let memory: UInt64 = 13
        static let temperature: UInt64 = 14
    }

    private enum Waves {
        static let cpu = [2.7, 5.3, 11.1, 23.5]
        static let memory = [0.8, 1.7]
        static let temperature = [1.1, 2.3]
    }

    static func profile(for scenario: DemoScenario) -> Profile {
        switch scenario {
        case .charging:
            return Profile(
                cpu: CPUUsage(userPercent: 15.2, systemPercent: 8.6),
                memory: memoryUsage(appGiB: 6.2, wiredGiB: 2.1, compressedGiB: 1.5, totalGiB: 16),
                socMaxCelsius: 41.2,
                socAverageCelsius: 38.9
            )
        case .battery:
            return Profile(
                cpu: CPUUsage(userPercent: 8.1, systemPercent: 3.6),
                memory: memoryUsage(appGiB: 5.4, wiredGiB: 1.9, compressedGiB: 1.3, totalGiB: 16),
                socMaxCelsius: 36.4,
                socAverageCelsius: 34.5
            )
        case .draining:
            return Profile(
                cpu: CPUUsage(userPercent: 58.4, systemPercent: 17.6),
                memory: memoryUsage(appGiB: 8.9, wiredGiB: 2.4, compressedGiB: 2.1, totalGiB: 16),
                socMaxCelsius: 69.8,
                socAverageCelsius: 64.2
            )
        case .desktop:
            return Profile(
                cpu: CPUUsage(userPercent: 6.2, systemPercent: 2.9),
                memory: memoryUsage(appGiB: 9.9, wiredGiB: 3.2, compressedGiB: 1.6, totalGiB: 32),
                socMaxCelsius: 34.1,
                socAverageCelsius: 32.6
            )
        }
    }

    static func current(for scenario: DemoScenario, at date: Date) -> SystemStats {
        let profile = profile(for: scenario)
        return SystemStats(
            date: date,
            cpu: profile.cpu,
            memory: profile.memory,
            temperature: temperature(max: profile.socMaxCelsius, average: profile.socAverageCelsius)
        )
    }

    static func history(for scenario: DemoScenario, endingAt date: Date) -> [SystemStats] {
        let profile = profile(for: scenario)
        let cpuSignal = DemoSignal(seed: Seed.cpu, cyclesPerWindow: Waves.cpu)
        let memorySignal = DemoSignal(seed: Seed.memory, cyclesPerWindow: Waves.memory)
        let temperatureSignal = DemoSignal(seed: Seed.temperature, cyclesPerWindow: Waves.temperature)
        var jitter = SeededGenerator(seed: Seed.cpuJitter)

        let window = RefreshCadence.statsWindow
        let steps = Int(window / historyInterval)
        let latestLoad = profile.cpu.totalPercent
        let latestMemoryPercent = profile.memory.usedPercent

        return (0...steps).map { step in
            let secondsAgo = window - Double(step) * historyInterval
            let noise = secondsAgo == 0 ? 0 : (jitter.nextUnit() - 0.5) * 2 * Swing.cpuJitterShareOfLoad * latestLoad

            let load = max(
                Swing.minimumCPUPercent,
                latestLoad * (1 + Swing.cpuShareOfLoad * cpuSignal.deviation(secondsAgo: secondsAgo)) + noise
            )
            let memoryPercent = latestMemoryPercent
                + Swing.memoryPercent * memorySignal.deviation(secondsAgo: secondsAgo)
                - Swing.memoryDriftPercent * secondsAgo / window
            let socShift = Swing.socCelsius * temperatureSignal.deviation(secondsAgo: secondsAgo)

            return SystemStats(
                date: date.addingTimeInterval(-secondsAgo),
                cpu: scaled(profile.cpu, toTotal: load),
                memory: scaled(profile.memory, by: memoryPercent / latestMemoryPercent),
                temperature: temperature(
                    max: profile.socMaxCelsius + socShift,
                    average: profile.socAverageCelsius + socShift
                )
            )
        }
    }

    private static func memoryUsage(appGiB: Double, wiredGiB: Double, compressedGiB: Double, totalGiB: Double) -> MemoryUsage {
        let app = bytes(gibibytes: appGiB)
        let wired = bytes(gibibytes: wiredGiB)
        let compressed = bytes(gibibytes: compressedGiB)
        return MemoryUsage(
            usedBytes: app + wired + compressed,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: bytes(gibibytes: totalGiB),
            swapUsedBytes: 0
        )
    }

    private static func bytes(gibibytes: Double) -> UInt64 {
        UInt64(gibibytes * bytesPerGibibyte)
    }

    private static func scaled(_ cpu: CPUUsage, toTotal total: Double) -> CPUUsage {
        let factor = total / cpu.totalPercent
        return CPUUsage(userPercent: cpu.userPercent * factor, systemPercent: cpu.systemPercent * factor)
    }

    private static func scaled(_ memory: MemoryUsage, by factor: Double) -> MemoryUsage {
        let app = UInt64(Double(memory.appBytes) * factor)
        let wired = UInt64(Double(memory.wiredBytes) * factor)
        let compressed = UInt64(Double(memory.compressedBytes) * factor)
        return MemoryUsage(
            usedBytes: app + wired + compressed,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: memory.totalBytes,
            swapUsedBytes: memory.swapUsedBytes
        )
    }

    private static func temperature(max: Double, average: Double) -> TemperatureReadings {
        TemperatureReadings(socMaxCelsius: max, socAverageCelsius: average, sensorCount: sensorCount)
    }
}
