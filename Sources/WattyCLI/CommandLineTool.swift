import Foundation
import WattyCore

public enum CommandLineTool {
    public static func run(arguments: [String]) async -> Int32 {
        await run(arguments: arguments, context: .live())
    }

    static func run(arguments: [String], context: CommandContext) async -> Int32 {
        let command: Command
        do {
            command = try CommandParser.parse(arguments)
        } catch let error as UsageError {
            context.console.writeError(HelpText.usageErrorText(for: error))
            return ExitCode.usage
        } catch {
            return context.reportFailure("unexpected error while reading arguments: \(error)")
        }
        return await execute(command, context: context)
    }

    static func execute(_ command: Command, context: CommandContext) async -> Int32 {
        switch command {
        case .status(let options):
            return await StatusCommand.run(options, context: context)
        case .top(let options):
            return await TopCommand.run(options, context: context)
        case .watch(let options):
            return await WatchCommand.run(options, context: context)
        case .show:
            return await ShowCommand.run(context: context)
        case .help(let topic):
            context.console.write(HelpText.text(for: topic, version: WattyVersion.current))
            return ExitCode.success
        case .version:
            context.console.write("\(CLIDefaults.toolName) \(WattyVersion.current)\n")
            return ExitCode.success
        }
    }
}
