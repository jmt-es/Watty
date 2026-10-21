import Darwin
import XCTest
@testable import WattyCLI

final class TerminalEnvironmentTests: XCTestCase {
    private func detect(_ environment: [String: String]) -> TerminalEnvironment {
        let descriptor = open("/dev/null", O_WRONLY)
        defer { close(descriptor) }
        return TerminalEnvironment.detect(environment: environment, descriptor: descriptor)
    }

    func testPipedOutputIsNotInteractiveAndNeverStyled() {
        let environment = detect(["TERM": "xterm-256color"])

        XCTAssertFalse(environment.isInteractive)
        XCTAssertFalse(environment.supportsCursorControl)
        XCTAssertFalse(environment.usesStyle)
        XCTAssertFalse(environment.style.isEnabled)
    }

    func testNoColorDisablesStyleOnlyWhenNotEmpty() {
        XCTAssertTrue(detect(["NO_COLOR": "1"]).colorDisabled)
        XCTAssertTrue(detect(["NO_COLOR": "anything"]).colorDisabled)
        XCTAssertFalse(detect(["NO_COLOR": ""]).colorDisabled)
        XCTAssertFalse(detect([:]).colorDisabled)
    }

    func testColumnsFallBackToTheEnvironmentThenTo80() {
        XCTAssertEqual(detect(["COLUMNS": "132"]).columns, 132)
        XCTAssertEqual(detect(["COLUMNS": "abc"]).columns, 80)
        XCTAssertEqual(detect(["COLUMNS": "0"]).columns, 80)
        XCTAssertEqual(detect([:]).columns, 80)
    }

    func testInteractiveTerminalStylesUnlessNoColorOrDumb() {
        XCTAssertTrue(TerminalEnvironment(isInteractive: true, term: "xterm-256color").usesStyle)
        XCTAssertFalse(TerminalEnvironment(isInteractive: true, term: "xterm", colorDisabled: true).usesStyle)
        XCTAssertFalse(TerminalEnvironment(isInteractive: true, term: "dumb").usesStyle)
        XCTAssertFalse(TerminalEnvironment(isInteractive: false, term: "xterm").usesStyle)
    }

    func testNoColorStillAllowsCursorControlForTheLiveView() {
        let environment = TerminalEnvironment(isInteractive: true, term: "xterm", colorDisabled: true)

        XCTAssertTrue(environment.supportsCursorControl)
    }

    func testDumbTerminalsCannotRedrawInPlace() {
        XCTAssertFalse(TerminalEnvironment(isInteractive: true, term: "dumb").supportsCursorControl)
        XCTAssertFalse(TerminalEnvironment(isInteractive: true, term: "DUMB").supportsCursorControl)
        XCTAssertTrue(TerminalEnvironment(isInteractive: true, term: nil).supportsCursorControl)
    }
}

final class TextStyleTests: XCTestCase {
    func testDisabledStyleReturnsTextUntouched() {
        let style = TextStyle.plain

        XCTAssertEqual(style.bold("x"), "x")
        XCTAssertEqual(style.dim("x"), "x")
        XCTAssertEqual(style.red("x"), "x")
        XCTAssertEqual(style.green("x"), "x")
        XCTAssertEqual(style.yellow("x"), "x")
    }

    func testEnabledStyleWrapsWithResetAfterTheText() {
        let style = TextStyle(isEnabled: true)

        XCTAssertEqual(style.bold("x"), "\u{1B}[1mx\u{1B}[0m")
        XCTAssertEqual(style.dim("x"), "\u{1B}[2mx\u{1B}[0m")
        XCTAssertEqual(style.red("x"), "\u{1B}[31mx\u{1B}[0m")
        XCTAssertEqual(style.green("x"), "\u{1B}[32mx\u{1B}[0m")
        XCTAssertEqual(style.yellow("x"), "\u{1B}[33mx\u{1B}[0m")
    }

    func testEmptyTextIsNeverWrapped() {
        XCTAssertEqual(TextStyle(isEnabled: true).bold(""), "")
    }
}
