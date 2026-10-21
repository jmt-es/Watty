import Darwin
import Foundation

struct TerminalEnvironment: Equatable {
    static let fallbackColumns = 80

    var isInteractive: Bool
    var term: String?
    var colorDisabled: Bool
    var columns: Int

    init(
        isInteractive: Bool,
        term: String? = nil,
        colorDisabled: Bool = false,
        columns: Int = TerminalEnvironment.fallbackColumns
    ) {
        self.isInteractive = isInteractive
        self.term = term
        self.colorDisabled = colorDisabled
        self.columns = columns
    }

    var supportsCursorControl: Bool {
        isInteractive && term?.lowercased() != "dumb"
    }

    var usesStyle: Bool {
        supportsCursorControl && !colorDisabled
    }

    var style: TextStyle {
        TextStyle(isEnabled: usesStyle)
    }

    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        descriptor: Int32 = STDOUT_FILENO
    ) -> TerminalEnvironment {
        TerminalEnvironment(
            isInteractive: isatty(descriptor) == 1,
            term: environment["TERM"],
            colorDisabled: !(environment["NO_COLOR"] ?? "").isEmpty,
            columns: columns(of: descriptor, environment: environment)
        )
    }

    private static func columns(of descriptor: Int32, environment: [String: String]) -> Int {
        var size = winsize()
        if ioctl(descriptor, TIOCGWINSZ, &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col)
        }
        if let text = environment["COLUMNS"], let value = Int(text), value > 0 {
            return value
        }
        return fallbackColumns
    }
}

struct TextStyle: Equatable {
    private static let escape = "\u{1B}["
    private static let reset = "\u{1B}[0m"

    let isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    static let plain = TextStyle(isEnabled: false)

    func bold(_ text: String) -> String { wrap(text, code: 1) }
    func dim(_ text: String) -> String { wrap(text, code: 2) }
    func red(_ text: String) -> String { wrap(text, code: 31) }
    func green(_ text: String) -> String { wrap(text, code: 32) }
    func yellow(_ text: String) -> String { wrap(text, code: 33) }

    private func wrap(_ text: String, code: Int) -> String {
        guard isEnabled, !text.isEmpty else { return text }
        return "\(Self.escape)\(code)m\(text)\(Self.reset)"
    }
}
