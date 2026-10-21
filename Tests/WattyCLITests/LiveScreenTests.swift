import XCTest
@testable import WattyCLI

final class LiveScreenTests: XCTestCase {
    private final class Sink {
        var writes: [String] = []
    }

    private func makeScreen() -> (LiveScreen, Sink) {
        let sink = Sink()
        return (LiveScreen { sink.writes.append($0) }, sink)
    }

    func testOpenEntersTheAlternateScreenAndHidesTheCursor() {
        let (screen, sink) = makeScreen()

        screen.open()

        XCTAssertEqual(sink.writes, ["\u{1B}[?1049h\u{1B}[?25l"])
    }

    func testDrawRewritesFromTheTopAndClearsLeftovers() {
        let (screen, sink) = makeScreen()
        screen.open()

        screen.draw(["one", "two"])

        XCTAssertEqual(sink.writes.last, "\u{1B}[Hone\u{1B}[K\ntwo\u{1B}[K\u{1B}[J")
    }

    func testCloseRestoresCursorAndScreenExactlyOnce() {
        let (screen, sink) = makeScreen()
        screen.open()

        screen.close()
        screen.close()

        XCTAssertEqual(sink.writes, ["\u{1B}[?1049h\u{1B}[?25l", "\u{1B}[?25h\u{1B}[?1049l"])
    }

    func testNothingIsDrawnBeforeOpenOrAfterClose() {
        let (screen, sink) = makeScreen()

        screen.draw(["early"])
        screen.open()
        screen.close()
        screen.draw(["late"])

        XCTAssertEqual(sink.writes.count, 2)
    }

    func testCloseWithoutOpenWritesNothing() {
        let (screen, sink) = makeScreen()

        screen.close()

        XCTAssertTrue(sink.writes.isEmpty)
    }
}
