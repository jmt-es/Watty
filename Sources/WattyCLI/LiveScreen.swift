import Darwin
import Foundation

enum ScreenSequence {
    static let enterLiveScreen = "\u{1B}[?1049h\u{1B}[?25l"
    static let leaveLiveScreen = "\u{1B}[?25h\u{1B}[?1049l"
    static let cursorHome = "\u{1B}[H"
    static let clearLineRemainder = "\u{1B}[K"
    static let clearScreenBelow = "\u{1B}[J"
}

final class LiveScreen {
    private let lock = NSLock()
    private let output: (String) -> Void
    private var isOpen = false

    init(output: @escaping (String) -> Void) {
        self.output = output
    }

    func open() {
        lock.lock()
        defer { lock.unlock() }
        guard !isOpen else { return }
        isOpen = true
        output(ScreenSequence.enterLiveScreen)
    }

    func draw(_ lines: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { return }
        let body = lines.map { $0 + ScreenSequence.clearLineRemainder }.joined(separator: "\n")
        output(ScreenSequence.cursorHome + body + ScreenSequence.clearScreenBelow)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { return }
        isOpen = false
        output(ScreenSequence.leaveLiveScreen)
    }
}

final class TerminationSignalHandlers {
    private typealias Handler = @convention(c) (Int32) -> Void

    private static let handledSignals = [SIGINT, SIGTERM, SIGQUIT]

    private var sources: [DispatchSourceSignal] = []
    private var previousHandlers: [(number: Int32, handler: Handler?)] = []

    init(onTerminate cleanup: @escaping () -> Void) {
        for number in Self.handledSignals {
            previousHandlers.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                cleanup()
                signal(number, SIG_DFL)
                raise(number)
            }
            source.resume()
            sources.append(source)
        }
    }

    func remove() {
        for source in sources {
            source.cancel()
        }
        for previous in previousHandlers {
            signal(previous.number, previous.handler)
        }
        sources.removeAll()
        previousHandlers.removeAll()
    }
}
