import Foundation

struct UsageError: Error, Equatable {
    let message: String
    let topic: HelpTopic

    init(_ message: String, topic: HelpTopic) {
        self.message = message
        self.topic = topic
    }
}

enum CommandParser {
    private static let helpFlags: Set<String> = ["-h", "--help"]
    private static let versionFlags: Set<String> = ["--version", "-v"]

    static func parse(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first else { return .status(StatusOptions()) }
        let rest = Array(arguments.dropFirst())

        if helpFlags.contains(name) { return .help(.overview) }
        if versionFlags.contains(name) {
            if let extra = rest.first { throw unexpectedArgument(extra, topic: .overview) }
            return .version
        }

        switch name {
        case "help": return try parseHelp(rest)
        case "status": return try parseStatus(rest)
        case "top": return try parseTop(rest)
        case "watch": return try parseWatch(rest)
        case "show": return try parseShow(rest)
        default:
            let kind = name.hasPrefix("-") ? "option" : "command"
            throw UsageError("unknown \(kind) '\(name)'", topic: .overview)
        }
    }

    private static func parseHelp(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first, !helpFlags.contains(name) else { return .help(.overview) }
        if let extra = arguments.dropFirst().first { throw unexpectedArgument(extra, topic: .overview) }
        guard let topic = HelpTopic(commandName: name) else {
            throw UsageError("unknown command '\(name)'", topic: .overview)
        }
        return .help(topic)
    }

    private static func parseStatus(_ arguments: [String]) throws -> Command {
        if requestsHelp(arguments) { return .help(.status) }
        var options = StatusOptions()
        var scanner = OptionScanner(arguments, topic: .status)
        while let option = scanner.next() {
            switch option.name {
            case "--json":
                try scanner.requireNoValue(option)
                options.json = true
            default:
                throw scanner.unrecognized(option)
            }
        }
        return .status(options)
    }

    private static func parseTop(_ arguments: [String]) throws -> Command {
        if requestsHelp(arguments) { return .help(.top) }
        var options = TopOptions()
        var scanner = OptionScanner(arguments, topic: .top)
        while let option = scanner.next() {
            switch option.name {
            case "--json":
                try scanner.requireNoValue(option)
                options.json = true
            case "--limit":
                options.limit = try parseLimit(try scanner.value(for: option), topic: .top)
            case "--interval":
                options.interval = try parseInterval(try scanner.value(for: option), topic: .top)
            default:
                throw scanner.unrecognized(option)
            }
        }
        return .top(options)
    }

    private static func parseWatch(_ arguments: [String]) throws -> Command {
        if requestsHelp(arguments) { return .help(.watch) }
        var options = WatchOptions()
        var scanner = OptionScanner(arguments, topic: .watch)
        while let option = scanner.next() {
            switch option.name {
            case "--interval":
                options.interval = try parseInterval(try scanner.value(for: option), topic: .watch)
            default:
                throw scanner.unrecognized(option)
            }
        }
        return .watch(options)
    }

    private static func parseShow(_ arguments: [String]) throws -> Command {
        if requestsHelp(arguments) { return .help(.show) }
        var scanner = OptionScanner(arguments, topic: .show)
        if let option = scanner.next() { throw scanner.unrecognized(option) }
        return .show
    }

    private static func requestsHelp(_ arguments: [String]) -> Bool {
        arguments.contains { helpFlags.contains($0) }
    }

    private static func parseLimit(_ text: String, topic: HelpTopic) throws -> Int {
        guard let value = Int(text), value > 0 else {
            throw UsageError("invalid value '\(text)' for '--limit': expected a positive integer", topic: topic)
        }
        return value
    }

    private static func parseInterval(_ text: String, topic: HelpTopic) throws -> TimeInterval {
        let range = CLIDefaults.minimumInterval...CLIDefaults.maximumInterval
        guard let value = Double(text), value.isFinite, range.contains(value) else {
            let bounds = "\(formatted(range.lowerBound)) and \(formatted(range.upperBound))"
            throw UsageError("invalid value '\(text)' for '--interval': expected seconds between \(bounds)", topic: topic)
        }
        return value
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%g", value)
    }

    fileprivate static func unexpectedArgument(_ argument: String, topic: HelpTopic) -> UsageError {
        let context = topic == .overview ? "" : " for '\(topic.rawValue)'"
        let kind = argument.hasPrefix("-") ? "unknown option" : "unexpected argument"
        return UsageError("\(kind) '\(argument)'\(context)", topic: topic)
    }
}

private struct Option {
    let raw: String
    let name: String
    let inlineValue: String?
}

private struct OptionScanner {
    private var remaining: ArraySlice<String>
    private let topic: HelpTopic

    init(_ arguments: [String], topic: HelpTopic) {
        remaining = arguments[...]
        self.topic = topic
    }

    mutating func next() -> Option? {
        guard let argument = remaining.popFirst() else { return nil }
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else {
            return Option(raw: argument, name: argument, inlineValue: nil)
        }
        return Option(
            raw: argument,
            name: String(argument[..<equals]),
            inlineValue: String(argument[argument.index(after: equals)...])
        )
    }

    mutating func value(for option: Option) throws -> String {
        if let inline = option.inlineValue { return inline }
        guard let value = remaining.popFirst() else {
            throw UsageError("option '\(option.name)' requires a value", topic: topic)
        }
        return value
    }

    func requireNoValue(_ option: Option) throws {
        guard option.inlineValue == nil else {
            throw UsageError("option '\(option.name)' does not take a value", topic: topic)
        }
    }

    func unrecognized(_ option: Option) -> UsageError {
        CommandParser.unexpectedArgument(option.raw, topic: topic)
    }
}
