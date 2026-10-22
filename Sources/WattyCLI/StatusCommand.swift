import Foundation
import WattyCore

enum StatusCommand {
    static func run(_ options: StatusOptions, context: CommandContext) async -> Int32 {
        var snapshot = await context.telemetry.snapshot()
        snapshot.netFlow = NetFlowEstimator.instantaneousEstimate(for: snapshot)
        _ = await context.telemetry.systemStats()
        _ = await context.pause(CLIDefaults.cpuSamplingWindow)
        let stats = await context.telemetry.systemStats()

        let report = StatusReport(snapshot: snapshot, stats: stats, generatedAt: context.now())
        context.reportWarnings(report.warnings)

        if options.json {
            return JSONOutput.write(report, to: context)
        }
        let lines = StatusRenderer.lines(for: report, style: context.terminal.style)
        context.console.write(lines.joined(separator: "\n") + "\n")
        return ExitCode.success
    }
}
