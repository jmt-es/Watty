import XCTest
import WattyCore
@testable import WattyCLI

final class CommandLineToolTests: XCTestCase {
    func testUnknownCommandIsAUsageError() async {
        let rig = TestRig()

        let code = await rig.run("stats")

        XCTAssertEqual(code, 64)
        XCTAssertEqual(rig.console.output, "")
        XCTAssertEqual(rig.console.errors, """
        watty: unknown command 'stats'
        usage: watty [status|top|watch|show|help] [options]
        Try 'watty --help' for more information.

        """)
        XCTAssertEqual(rig.telemetry.snapshotCalls, 0)
    }

    func testBadOptionValuesAreUsageErrorsWithTheCommandUsage() async {
        let limit = TestRig()
        let interval = TestRig()

        let limitCode = await limit.run("top", "--limit", "abc")
        let intervalCode = await interval.run("watch", "--interval", "0")

        XCTAssertEqual(limitCode, 64)
        XCTAssertEqual(intervalCode, 64)
        XCTAssertTrue(limit.console.errors.contains("usage: watty top [--json] [--limit N] [--interval SECONDS]"))
        XCTAssertTrue(interval.console.errors.contains("invalid value '0' for '--interval'"))
        XCTAssertEqual(limit.console.output + interval.console.output, "")
    }

    func testHelpGoesToStdoutWithSuccess() async {
        let rig = TestRig()

        let code = await rig.run("help")
        let flagCode = await rig.run("top", "--help")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(flagCode, 0)
        XCTAssertTrue(rig.console.output.contains("Usage:\n  watty [status|top|watch|show|help] [options]"))
        XCTAssertTrue(rig.console.output.contains("Usage: watty top"))
        XCTAssertEqual(rig.console.errors, "")
        XCTAssertEqual(rig.telemetry.snapshotCalls, 0)
    }

    func testVersionPrintsTheToolNameAndVersion() async {
        let rig = TestRig()

        let code = await rig.run("--version")

        XCTAssertEqual(code, 0)
        XCTAssertEqual(rig.console.output, "watty \(WattyVersion.current)\n")
    }
}
