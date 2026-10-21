import Foundation
import WattyCore

enum WatchCommand {
    static func run(_ options: WatchOptions, context: CommandContext) async -> Int32 {
        if context.terminal.supportsCursorControl {
            return await runLive(options, context: context)
        }
        return await runLines(options, context: context)
    }

    private static func runLines(_ options: WatchOptions, context: CommandContext) async -> Int32 {
        var reportedWarnings = Set<String>()
        while true {
            let startedAt = context.now()
            let snapshot = await context.telemetry.snapshot()
            let report = StatusReport(snapshot: snapshot, stats: emptyStats(at: startedAt), generatedAt: startedAt)

            context.reportWarnings(report.warnings.filter { reportedWarnings.insert($0).inserted })
            context.console.write(WatchRenderer.line(report: report, date: startedAt, timeZone: context.timeZone) + "\n")

            guard await context.pause(remaining(of: options.interval, since: startedAt, context: context)) else {
                return ExitCode.success
            }
        }
    }

    private static func runLive(_ options: WatchOptions, context: CommandContext) async -> Int32 {
        let screen = LiveScreen(output: context.console.write)
        let handlers = TerminationSignalHandlers(onTerminate: screen.close)
        screen.open()
        defer {
            screen.close()
            handlers.remove()
        }

        _ = await context.telemetry.systemStats()
        guard await context.pause(CLIDefaults.cpuSamplingWindow) else { return ExitCode.success }

        while true {
            let startedAt = context.now()
            let snapshot = await context.telemetry.snapshot()
            let stats = await context.telemetry.systemStats()
            let report = StatusReport(snapshot: snapshot, stats: stats, generatedAt: context.now())

            screen.draw(WatchRenderer.frame(
                report: report,
                interval: options.interval,
                date: context.now(),
                style: context.terminal.style
            ))

            guard await context.pause(remaining(of: options.interval, since: startedAt, context: context)) else {
                return ExitCode.success
            }
        }
    }

    private static func remaining(of interval: TimeInterval, since startedAt: Date, context: CommandContext) -> TimeInterval {
        max(0, interval - context.now().timeIntervalSince(startedAt))
    }

    private static func emptyStats(at date: Date) -> SystemStats {
        SystemStats(date: date, cpu: nil, memory: nil, temperature: nil)
    }
}
