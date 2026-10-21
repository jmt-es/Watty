import XCTest
@testable import WattyCore

final class ServiceActionResultTests: XCTestCase {
    private enum Command {
        static let settings = "/usr/bin/pmset -g"
        static let capabilities = "/usr/bin/pmset -g cap"
        static let privilegedScriptPrefix = "/usr/bin/osascript -e"
    }

    private enum Output {
        static let automatic = "Currently in use:\n powermode 0\n"
        static let highPower = "Currently in use:\n powermode 2\n"
        static let capabilities = "Capabilities for AC Power:\n lowpowermode\n highpowermode\n"
    }

    private struct StubRunner: CommandRunning {
        let privileged: ProcessRunner.Result
        let settings: String

        func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> ProcessRunner.Result {
            let command = ([executable] + arguments).joined(separator: " ")
            switch command {
            case _ where command.hasPrefix(Command.privilegedScriptPrefix): return privileged
            case Command.settings: return Self.result(stdout: settings)
            case Command.capabilities: return Self.result(stdout: Output.capabilities)
            default: return Self.result(stdout: "", status: 127)
            }
        }

        static func result(stdout: String, status: Int32 = 0) -> ProcessRunner.Result {
            ProcessRunner.Result(stdout: stdout, stderr: "", terminationStatus: status, didTimeOut: false, duration: 0)
        }
    }

    private func setPowerMode(
        _ mode: PowerMode,
        privileged: ProcessRunner.Result,
        settingsAfterwards: String = Output.automatic
    ) async -> ServiceActionResult {
        let service = BatteryService(
            detailsLifetime: 300,
            dependencies: BatteryServiceDependencies(
                runner: StubRunner(privileged: privileged, settings: settingsAfterwards),
                readPowerSource: { .noInternalBattery },
                readSmartBattery: { .noService },
                now: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
        )
        return await service.setPowerMode(mode)
    }

    private func privilegedFailure(stderr: String, status: Int32 = 1, didTimeOut: Bool = false) -> ProcessRunner.Result {
        ProcessRunner.Result(stdout: "", stderr: stderr, terminationStatus: status, didTimeOut: didTimeOut, duration: 0)
    }

    func testReasonsKeepTheEnglishMessagesUsedByLogsAndTheCLI() {
        XCTAssertEqual(ServiceActionReason.applied(.lowPower).message, "Low Power applied")
        XCTAssertEqual(ServiceActionReason.systemKeptMode(.highPower).message, "System kept High Power")
        XCTAssertEqual(ServiceActionReason.canceled.message, "Authorization canceled")
        XCTAssertEqual(ServiceActionReason.timedOut.message, "Authorization timed out")
        XCTAssertEqual(ServiceActionReason.failed(detail: nil).message, "Power mode update failed")
        XCTAssertEqual(ServiceActionReason.failed(detail: "not authorized (-60007)").message, "not authorized (-60007)")
    }

    func testOnlyAnAppliedModeIsASuccess() {
        XCTAssertTrue(ServiceActionReason.applied(.automatic).isSuccess)
        XCTAssertFalse(ServiceActionReason.systemKeptMode(.automatic).isSuccess)
        XCTAssertFalse(ServiceActionReason.canceled.isSuccess)
        XCTAssertFalse(ServiceActionReason.timedOut.isSuccess)
        XCTAssertFalse(ServiceActionReason.failed(detail: nil).isSuccess)
    }

    func testResultDerivesSuccessAndMessageFromItsReason() {
        let applied = ServiceActionResult(reason: .applied(.highPower), resultingMode: .highPower)
        XCTAssertTrue(applied.success)
        XCTAssertEqual(applied.message, "High Power applied")
        XCTAssertEqual(applied.resultingMode, .highPower)

        let canceled = ServiceActionResult(reason: .canceled)
        XCTAssertFalse(canceled.success)
        XCTAssertEqual(canceled.message, "Authorization canceled")
        XCTAssertNil(canceled.resultingMode)
    }

    func testSettingAModeReportsItAsApplied() async {
        let result = await setPowerMode(.highPower, privileged: StubRunner.result(stdout: ""), settingsAfterwards: Output.highPower)

        XCTAssertEqual(result.reason, .applied(.highPower))
        XCTAssertEqual(result.resultingMode, .highPower)
        XCTAssertTrue(result.success)
    }

    func testSettingAModeReportsWhenTheSystemKeepsAnotherOne() async {
        let result = await setPowerMode(.lowPower, privileged: StubRunner.result(stdout: ""), settingsAfterwards: Output.automatic)

        XCTAssertEqual(result.reason, .systemKeptMode(.automatic))
        XCTAssertEqual(result.resultingMode, .automatic)
        XCTAssertEqual(result.message, "System kept Automatic")
        XCTAssertFalse(result.success)
    }

    func testDismissingTheAuthorizationDialogReportsCanceled() async {
        let byCode = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: "execution error: Error. (-128)"))
        let byText = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: "execution error: user canceled"))

        XCTAssertEqual(byCode.reason, .canceled)
        XCTAssertEqual(byText.reason, .canceled)
        XCTAssertEqual(byCode.resultingMode, .automatic)
    }

    func testCancellationWinsOverATimeout() async {
        let result = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: "(-128)", status: 124, didTimeOut: true))

        XCTAssertEqual(result.reason, .canceled)
    }

    func testAnUnansweredAuthorizationDialogReportsTimedOut() async {
        let result = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: "", status: 124, didTimeOut: true))

        XCTAssertEqual(result.reason, .timedOut)
        XCTAssertFalse(result.success)
    }

    func testAFailureKeepsTheErrorOutputAsDetail() async {
        let result = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: "  execution error: not authorized (-60007)\n"))

        XCTAssertEqual(result.reason, .failed(detail: "execution error: not authorized (-60007)"))
        XCTAssertEqual(result.message, "execution error: not authorized (-60007)")
    }

    func testAFailureWithoutOutputHasNoDetail() async {
        let result = await setPowerMode(.lowPower, privileged: privilegedFailure(stderr: " \n"))

        XCTAssertEqual(result.reason, .failed(detail: nil))
        XCTAssertEqual(result.message, "Power mode update failed")
    }
}
