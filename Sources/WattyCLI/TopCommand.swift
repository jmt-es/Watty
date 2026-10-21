import Foundation
import WattyCore

enum TopCommand {
    static func run(_ options: TopOptions, context: CommandContext) async -> Int32 {
        _ = await context.telemetry.energySample()
        _ = await context.pause(options.interval)
        let sample = await context.telemetry.energySample()
        guard !sample.failed, !sample.isWarmingUp else {
            return context.reportFailure("could not sample the running processes (the sampler returned no data)")
        }

        let report = TopReport(
            sample: sample,
            limit: options.limit,
            intervalSeconds: options.interval,
            generatedAt: context.now()
        )
        if options.json {
            return JSONOutput.write(report, to: context)
        }
        let terminal = context.terminal
        let lines = TopRenderer.lines(
            for: report,
            columns: terminal.isInteractive ? terminal.columns : nil,
            style: terminal.style
        )
        context.console.write(lines.joined(separator: "\n") + "\n")
        return ExitCode.success
    }
}
