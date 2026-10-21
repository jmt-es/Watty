import AppKit
import Foundation

struct LaunchOptions: Equatable {
    enum Appearance: String, Equatable {
        case light
        case dark

        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .dark ? .darkAqua : .aqua)
        }
    }

    struct Capture: Equatable {
        enum Target: Equatable {
            case panel
            case settings
        }

        let target: Target
        let outputURL: URL
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case missingValue(String)
        case unexpectedValue(String)
        case invalidAppearance(String)
        case invalidDemoScenario(String)
        case outputIsNotPNG(String)
        case conflictingCaptures
        case historyFileWithoutCapture
        case demoWithoutCapture
        case demoScenarioWithoutDemo
        case demoWithHistoryFile

        var errorDescription: String? {
            switch self {
            case .missingValue(let flag): return "\(flag) needs a value"
            case .unexpectedValue(let flag): return "\(flag) does not take a value"
            case .invalidAppearance(let value): return "--appearance must be light or dark, not \(value)"
            case .invalidDemoScenario(let value):
                let scenarios = DemoScenario.allCases.map(\.rawValue).joined(separator: ", ")
                return "--demo-scenario must be one of \(scenarios), not \(value)"
            case .outputIsNotPNG(let path): return "capture output must be a .png file, not \(path)"
            case .conflictingCaptures: return "use either --capture-panel or --capture-settings, not both"
            case .historyFileWithoutCapture: return "--history-file only works together with --capture-panel or --capture-settings"
            case .demoWithoutCapture: return "--demo only works together with --capture-panel or --capture-settings"
            case .demoScenarioWithoutDemo: return "--demo-scenario needs --demo"
            case .demoWithHistoryFile: return "--demo provides its own history, so it cannot be combined with --history-file"
            }
        }
    }

    static let capturePanelFlag = "--capture-panel"
    static let captureSettingsFlag = "--capture-settings"
    static let appearanceFlag = "--appearance"
    static let historyFileFlag = "--history-file"
    static let demoFlag = "--demo"
    static let demoScenarioFlag = "--demo-scenario"
    static let usageExitCode: Int32 = 64

    var capture: Capture?
    var appearance: Appearance?
    var historyFileURL: URL?
    var demoScenario: DemoScenario?

    var isCapturing: Bool {
        capture != nil
    }

    static let current: LaunchOptions = {
        do {
            return try parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("watty: \(error.localizedDescription)\n".utf8))
            exit(usageExitCode)
        }
    }()

    static func parse(_ arguments: [String]) throws -> LaunchOptions {
        var options = LaunchOptions()
        var index = 0
        var demoRequested = false
        var requestedScenario: DemoScenario?

        func value(for flag: String, inline: String?) throws -> String {
            if let inline { return inline }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw ParseError.missingValue(flag)
            }
            index += 1
            return arguments[index]
        }

        while index < arguments.count {
            let (flag, inline) = split(arguments[index])
            switch flag {
            case capturePanelFlag, captureSettingsFlag:
                guard options.capture == nil else { throw ParseError.conflictingCaptures }
                let path = try value(for: flag, inline: inline)
                options.capture = Capture(
                    target: flag == capturePanelFlag ? .panel : .settings,
                    outputURL: try pngURL(for: path)
                )
            case appearanceFlag:
                let raw = try value(for: flag, inline: inline)
                guard let appearance = Appearance(rawValue: raw) else { throw ParseError.invalidAppearance(raw) }
                options.appearance = appearance
            case historyFileFlag:
                options.historyFileURL = fileURL(for: try value(for: flag, inline: inline))
            case demoFlag:
                guard inline == nil else { throw ParseError.unexpectedValue(flag) }
                demoRequested = true
            case demoScenarioFlag:
                let raw = try value(for: flag, inline: inline)
                guard let scenario = DemoScenario(rawValue: raw) else { throw ParseError.invalidDemoScenario(raw) }
                requestedScenario = scenario
            default:
                break
            }
            index += 1
        }

        if options.historyFileURL != nil, options.capture == nil {
            throw ParseError.historyFileWithoutCapture
        }
        if requestedScenario != nil, !demoRequested {
            throw ParseError.demoScenarioWithoutDemo
        }
        if demoRequested {
            guard options.capture != nil else { throw ParseError.demoWithoutCapture }
            guard options.historyFileURL == nil else { throw ParseError.demoWithHistoryFile }
            options.demoScenario = requestedScenario ?? .default
        }
        return options
    }

    private static func split(_ argument: String) -> (flag: String, inlineValue: String?) {
        guard argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") else { return (argument, nil) }
        return (String(argument[..<equals]), String(argument[argument.index(after: equals)...]))
    }

    private static func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func pngURL(for path: String) throws -> URL {
        let url = fileURL(for: path)
        guard url.pathExtension.lowercased() == "png" else { throw ParseError.outputIsNotPNG(path) }
        return url
    }
}
