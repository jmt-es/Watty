import Foundation
import WattyCore

protocol TelemetrySource {
    func snapshot() async -> BatterySnapshot
    func systemStats() async -> SystemStats
    func energySample() async -> EnergySample
}

struct LiveTelemetry: TelemetrySource {
    private let service: BatteryService

    init(service: BatteryService = .shared) {
        self.service = service
    }

    func snapshot() async -> BatterySnapshot {
        await service.fetchSnapshot(depth: .full)
    }

    func systemStats() async -> SystemStats {
        await service.fetchSystemStats()
    }

    func energySample() async -> EnergySample {
        await service.fetchEnergySample()
    }
}

struct CommandContext {
    var telemetry: TelemetrySource
    var console: ConsoleOutput
    var terminal: TerminalEnvironment
    var launcher: AppLauncher
    var timeZone: TimeZone
    var now: () -> Date
    var sleep: (TimeInterval) async throws -> Void

    init(
        telemetry: TelemetrySource,
        console: ConsoleOutput,
        terminal: TerminalEnvironment,
        launcher: AppLauncher,
        timeZone: TimeZone = .current,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async throws -> Void = CommandContext.sleepForReal
    ) {
        self.telemetry = telemetry
        self.console = console
        self.terminal = terminal
        self.launcher = launcher
        self.timeZone = timeZone
        self.now = now
        self.sleep = sleep
    }

    static func live() -> CommandContext {
        CommandContext(
            telemetry: LiveTelemetry(),
            console: StandardConsole(),
            terminal: TerminalEnvironment.detect(),
            launcher: WorkspaceAppLauncher()
        )
    }

    private static let nanosecondsPerSecond = 1_000_000_000.0

    static func sleepForReal(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * nanosecondsPerSecond))
    }

    func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await sleep(seconds)
            return true
        } catch {
            return false
        }
    }

    func reportWarnings(_ warnings: [String]) {
        for warning in warnings {
            console.writeError("\(CLIDefaults.toolName): warning: \(warning)\n")
        }
    }

    func reportFailure(_ message: String) -> Int32 {
        console.writeError("\(CLIDefaults.toolName): \(message)\n")
        return ExitCode.runtimeFailure
    }
}
