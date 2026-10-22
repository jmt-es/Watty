import Foundation

enum HelpText {
    static func text(for topic: HelpTopic, version: String) -> String {
        switch topic {
        case .overview: return overview(version: version)
        case .status: return statusHelp
        case .top: return topHelp
        case .watch: return watchHelp
        case .show: return showHelp
        }
    }

    static func usageLine(for topic: HelpTopic) -> String {
        let tool = CLIDefaults.toolName
        switch topic {
        case .overview: return "\(tool) [status|top|watch|show|help] [options]"
        case .status: return "\(tool) status [--json]"
        case .top: return "\(tool) top [--json] [--limit N] [--interval SECONDS]"
        case .watch: return "\(tool) watch [--interval SECONDS]"
        case .show: return "\(tool) show"
        }
    }

    static func usageErrorText(for error: UsageError) -> String {
        let tool = CLIDefaults.toolName
        let helpCommand = error.topic == .overview ? "\(tool) --help" : "\(tool) \(error.topic.rawValue) --help"
        return """
        \(tool): \(error.message)
        usage: \(usageLine(for: error.topic))
        Try '\(helpCommand)' for more information.

        """
    }

    private static func overview(version: String) -> String {
        """
        Watty \(version) - battery, power flow and energy telemetry for macOS

        Usage:
          \(usageLine(for: .overview))

        Commands:
          status   Battery, power flow, temperatures, CPU and memory (default)
          top      Apps using the most CPU
          watch    Live view that refreshes every few seconds
          show     Bring up the Watty panel
          help     Show help for a command

        Options:
          -h, --help       Show this help
          -v, --version    Print the version

        Run '\(CLIDefaults.toolName) <command> --help' for the options of a command.
        Exit codes: 0 success, 64 usage error, 1 runtime failure.

        """
    }

    private static let statusHelp = """
    Usage: \(usageLine(for: .status))

    Print battery level, charge state, time remaining, power flow, temperatures,
    CPU and memory use. Unknown values show as a dash in text and as null in JSON.

    Options:
      --json        Print one JSON document instead of text
      -h, --help    Show this help

    """

    private static let topHelp = """
    Usage: \(usageLine(for: .top))

    List the apps using the most CPU. CPU shares are averaged over the sampling
    interval.

    Options:
      --limit N            Apps to list (default \(CLIDefaults.topLimit))
      --interval SECONDS   Sampling interval, \(bound(CLIDefaults.minimumInterval)) to \(bound(CLIDefaults.maximumInterval)) (default \(bound(CLIDefaults.topInterval)))
      --json               Print one JSON document instead of a table
      -h, --help           Show this help

    """

    private static let watchHelp = """
    Usage: \(usageLine(for: .watch))

    Live view of the battery and power flow. On a terminal the screen refreshes in
    place until Ctrl-C. When output is piped, one line is printed per sample:

    <time> level=<percent> state=<state> battery_w=<watts> system_w=<watts>
      net_flow=<flow>

    net_flow is where the battery is really heading, judged over the last few
    minutes: charging, draining or holding. A dash means there is not enough data
    yet.

    Options:
      --interval SECONDS   Time between samples, \(bound(CLIDefaults.minimumInterval)) to \(bound(CLIDefaults.maximumInterval)) (default \(bound(CLIDefaults.watchInterval)))
      -h, --help           Show this help

    """

    private static let showHelp = """
    Usage: \(usageLine(for: .show))

    Bring up the Watty panel, starting the app first when it is not running.
    Useful when the menu bar icon is hidden behind the notch or a menu bar manager.

    Options:
      -h, --help    Show this help

    """

    private static func bound(_ seconds: TimeInterval) -> String {
        String(format: "%g", seconds)
    }
}
