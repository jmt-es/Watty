import XCTest
@testable import WattyCore

final class ProcessRunnerTests: XCTestCase {
    func testDrainsOutputLargerThanPipeBuffer() {
        let runner = ProcessRunner()

        let result = runner.run("/bin/sh", arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' a"], timeout: 5)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.count, 300000)
    }

    func testTerminatesProcessOnTimeout() {
        let runner = ProcessRunner()
        let startedAt = Date()

        let result = runner.run("/bin/sleep", arguments: ["10"], timeout: 0.3)

        XCTAssertTrue(result.didTimeOut)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 4)
    }

    func testReportsMissingExecutable() {
        let runner = ProcessRunner()

        let result = runner.run("/nonexistent/binary", arguments: [], timeout: 1)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.terminationStatus, -1)
    }
}
