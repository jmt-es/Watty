import Foundation
import WattyCore
@testable import WattyCLI

enum Fixtures {
    static let date = Date(timeIntervalSince1970: 1_792_598_644)

    static func snapshot(_ configure: (inout BatterySnapshot) -> Void = { _ in }) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.hasBattery = true
        snapshot.level = 72
        snapshot.isCharging = true
        snapshot.powerSource = .adapter
        snapshot.timeToFullMinutes = 98
        snapshot.voltageVolts = 12.3234
        snapshot.amperageAmps = 2.3814
        snapshot.batteryPowerWatts = 29.34056
        snapshot.systemPowerWatts = 59.8449
        snapshot.systemLoadWatts = 30.468
        snapshot.adapterRatedWatts = 70
        snapshot.cycleCount = 257
        snapshot.condition = "Normal"
        snapshot.maximumCapacityPercent = 89
        snapshot.temperatureCelsius = 30.634
        snapshot.powerMode = .highPower
        snapshot.lowPowerModeActive = false
        snapshot.lastUpdated = date
        configure(&snapshot)
        return snapshot
    }

    static func onBatterySnapshot(level: Int = 64, _ configure: (inout BatterySnapshot) -> Void = { _ in }) -> BatterySnapshot {
        snapshot {
            $0.level = level
            $0.isCharging = false
            $0.powerSource = .battery
            $0.timeToFullMinutes = nil
            $0.timeToEmptyMinutes = 215
            $0.adapterRatedWatts = nil
            $0.systemPowerWatts = 0
            $0.batteryPowerWatts = -11.24
            $0.amperageAmps = -0.91
            configure(&$0)
        }
    }

    static func noBatterySnapshot() -> BatterySnapshot {
        snapshot {
            $0.hasBattery = false
            $0.level = 0
            $0.isCharging = false
            $0.timeToFullMinutes = nil
            $0.voltageVolts = nil
            $0.amperageAmps = nil
            $0.batteryPowerWatts = nil
            $0.systemPowerWatts = nil
            $0.systemLoadWatts = nil
            $0.adapterRatedWatts = nil
            $0.cycleCount = nil
            $0.condition = nil
            $0.maximumCapacityPercent = nil
            $0.temperatureCelsius = nil
            $0.powerMode = .automatic
        }
    }

    static func stats(
        cpu: CPUUsage? = CPUUsage(userPercent: 8.14, systemPercent: 4.26),
        memory: MemoryUsage? = MemoryUsage(
            usedBytes: 19_000_000_000,
            appBytes: 12_000_000_000,
            wiredBytes: 4_000_000_000,
            compressedBytes: 3_000_000_000,
            totalBytes: 34_359_738_368,
            swapUsedBytes: 0
        ),
        temperature: TemperatureReadings? = TemperatureReadings(socMaxCelsius: 55.46, socAverageCelsius: 50.1, sensorCount: 4)
    ) -> SystemStats {
        SystemStats(date: date, cpu: cpu, memory: memory, temperature: temperature)
    }

    static func report(_ snapshot: BatterySnapshot? = nil, stats: SystemStats? = nil) -> StatusReport {
        StatusReport(snapshot: snapshot ?? self.snapshot(), stats: stats ?? self.stats(), generatedAt: date)
    }

    static func consumer(_ name: String, cpu: Double, memory: UInt64) -> EnergyConsumer {
        EnergyConsumer(id: name, name: name, pid: nil, cpuPercent: cpu, memoryBytes: memory, icon: nil)
    }

    static func energySample(_ consumers: [EnergyConsumer], warmingUp: Bool = false, failed: Bool = false) -> EnergySample {
        EnergySample(consumers: consumers, sampledAt: date, duration: 0.02, failed: failed, isWarmingUp: warmingUp)
    }

    static func topReport(_ consumers: [EnergyConsumer], limit: Int = 10, interval: Double = 1) -> TopReport {
        TopReport(sample: energySample(consumers), limit: limit, intervalSeconds: interval, generatedAt: date)
    }
}

func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
}

final class CapturingConsole: ConsoleOutput {
    private(set) var output = ""
    private(set) var errors = ""

    func write(_ text: String) {
        output += text
    }

    func writeError(_ text: String) {
        errors += text
    }

    var outputLines: [String] {
        output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

final class StubTelemetry: TelemetrySource {
    var snapshotValue: BatterySnapshot
    var statsValue: SystemStats
    var energySamples: [EnergySample]
    private(set) var snapshotCalls = 0
    private(set) var statsCalls = 0
    private(set) var energyCalls = 0

    init(
        snapshot: BatterySnapshot = Fixtures.snapshot(),
        stats: SystemStats = Fixtures.stats(),
        energySamples: [EnergySample] = [
            Fixtures.energySample([], warmingUp: true),
            Fixtures.energySample([
                Fixtures.consumer("Chrome", cpu: 41.26, memory: 2_000_000_000),
                Fixtures.consumer("WindowServer", cpu: 12.3, memory: 0),
                Fixtures.consumer("Slack", cpu: 4.04, memory: 900_000_000)
            ])
        ]
    ) {
        snapshotValue = snapshot
        statsValue = stats
        self.energySamples = energySamples
    }

    func snapshot() async -> BatterySnapshot {
        snapshotCalls += 1
        return snapshotValue
    }

    func systemStats() async -> SystemStats {
        statsCalls += 1
        return statsValue
    }

    func energySample() async -> EnergySample {
        energyCalls += 1
        return energySamples[min(energyCalls, energySamples.count) - 1]
    }
}

final class StubLauncher: AppLauncher {
    var running = false
    var installedURL: URL? = URL(fileURLWithPath: "/Applications/Watty.app")
    var launchError: Error?
    var becomesReady = true
    private(set) var events: [String] = []

    func isRunning(bundleIdentifier: String) -> Bool {
        events.append("isRunning \(bundleIdentifier)")
        return running
    }

    func postShowRequest() {
        events.append("post")
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        events.append("lookup \(bundleIdentifier)")
        return installedURL
    }

    func launch(applicationAt url: URL) async throws {
        events.append("launch \(url.path)")
        if let launchError { throw launchError }
    }

    func waitUntilReady(bundleIdentifier: String, timeout: TimeInterval) async -> Bool {
        events.append("wait \(Int(timeout))")
        return becomesReady
    }
}

final class SleepRecorder {
    private let allowedSleeps: Int?
    private(set) var durations: [TimeInterval] = []

    init(allowedSleeps: Int? = nil) {
        self.allowedSleeps = allowedSleeps
    }

    func sleep(_ seconds: TimeInterval) async throws {
        durations.append(seconds)
        if let allowedSleeps, durations.count > allowedSleeps {
            throw CancellationError()
        }
    }
}

struct TestRig {
    let console = CapturingConsole()
    let telemetry: StubTelemetry
    let launcher = StubLauncher()
    let sleeper: SleepRecorder
    let terminal: TerminalEnvironment
    let timeZone: TimeZone

    init(
        telemetry: StubTelemetry = StubTelemetry(),
        terminal: TerminalEnvironment = TerminalEnvironment(isInteractive: false),
        allowedSleeps: Int? = nil,
        timeZone: TimeZone = TimeZone(secondsFromGMT: 7200) ?? .current
    ) {
        self.telemetry = telemetry
        self.terminal = terminal
        self.timeZone = timeZone
        sleeper = SleepRecorder(allowedSleeps: allowedSleeps)
    }

    var context: CommandContext {
        CommandContext(
            telemetry: telemetry,
            console: console,
            terminal: terminal,
            launcher: launcher,
            timeZone: timeZone,
            now: { Fixtures.date },
            sleep: sleeper.sleep
        )
    }

    func run(_ arguments: String...) async -> Int32 {
        await CommandLineTool.run(arguments: arguments, context: context)
    }
}
