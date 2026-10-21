import Foundation

enum CLIDefaults {
    static let toolName = "watty"
    static let topLimit = 10
    static let topInterval: TimeInterval = 1
    static let watchInterval: TimeInterval = 2
    static let minimumInterval: TimeInterval = 0.5
    static let maximumInterval: TimeInterval = 3600
    static let cpuSamplingWindow: TimeInterval = 0.5
}

enum ExitCode {
    static let success: Int32 = 0
    static let runtimeFailure: Int32 = 1
    static let usage: Int32 = 64
}

struct StatusOptions: Equatable {
    var json: Bool

    init(json: Bool = false) {
        self.json = json
    }
}

struct TopOptions: Equatable {
    var json: Bool
    var limit: Int
    var interval: TimeInterval

    init(
        json: Bool = false,
        limit: Int = CLIDefaults.topLimit,
        interval: TimeInterval = CLIDefaults.topInterval
    ) {
        self.json = json
        self.limit = limit
        self.interval = interval
    }
}

struct WatchOptions: Equatable {
    var interval: TimeInterval

    init(interval: TimeInterval = CLIDefaults.watchInterval) {
        self.interval = interval
    }
}

enum HelpTopic: String, Equatable, CaseIterable {
    case overview
    case status
    case top
    case watch
    case show

    init?(commandName: String) {
        guard commandName != Self.overview.rawValue else { return nil }
        self.init(rawValue: commandName)
    }
}

enum Command: Equatable {
    case status(StatusOptions)
    case top(TopOptions)
    case watch(WatchOptions)
    case show
    case help(HelpTopic)
    case version
}
