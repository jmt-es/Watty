import XCTest
@testable import WattyCLI

final class CommandParserTests: XCTestCase {
    private func parse(_ arguments: String...) throws -> Command {
        try CommandParser.parse(arguments)
    }

    private func usageError(
        _ arguments: String...,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> UsageError? {
        do {
            let command = try CommandParser.parse(arguments)
            XCTFail("expected a usage error, got \(command)", file: file, line: line)
            return nil
        } catch let error as UsageError {
            return error
        } catch {
            XCTFail("unexpected error type \(error)", file: file, line: line)
            return nil
        }
    }

    func testNoArgumentsBehavesLikeStatus() throws {
        XCTAssertEqual(try parse(), .status(StatusOptions(json: false)))
    }

    func testStatusAcceptsTheJSONFlag() throws {
        XCTAssertEqual(try parse("status"), .status(StatusOptions(json: false)))
        XCTAssertEqual(try parse("status", "--json"), .status(StatusOptions(json: true)))
    }

    func testTopDefaults() throws {
        XCTAssertEqual(try parse("top"), .top(TopOptions(json: false, limit: 10, interval: 1)))
    }

    func testTopAcceptsAllOptionsInEitherForm() throws {
        XCTAssertEqual(
            try parse("top", "--json", "--limit", "5", "--interval", "0.5"),
            .top(TopOptions(json: true, limit: 5, interval: 0.5))
        )
        XCTAssertEqual(
            try parse("top", "--limit=3", "--interval=2.5"),
            .top(TopOptions(json: false, limit: 3, interval: 2.5))
        )
    }

    func testTopLastRepeatedOptionWins() throws {
        XCTAssertEqual(try parse("top", "--limit", "3", "--limit", "7"), .top(TopOptions(limit: 7)))
    }

    func testWatchDefaultsAndInterval() throws {
        XCTAssertEqual(try parse("watch"), .watch(WatchOptions(interval: 2)))
        XCTAssertEqual(try parse("watch", "--interval", "5"), .watch(WatchOptions(interval: 5)))
        XCTAssertEqual(try parse("watch", "--interval=0.5"), .watch(WatchOptions(interval: 0.5)))
    }

    func testShowTakesNoArguments() throws {
        XCTAssertEqual(try parse("show"), .show)
        XCTAssertEqual(usageError("show", "now")?.message, "unexpected argument 'now' for 'show'")
        XCTAssertEqual(usageError("show", "--json")?.message, "unknown option '--json' for 'show'")
    }

    func testGeneralHelpForms() throws {
        XCTAssertEqual(try parse("help"), .help(.overview))
        XCTAssertEqual(try parse("--help"), .help(.overview))
        XCTAssertEqual(try parse("-h"), .help(.overview))
    }

    func testHelpAboutHelpIsTheOverview() throws {
        XCTAssertEqual(try parse("help", "--help"), .help(.overview))
        XCTAssertEqual(try parse("help", "-h"), .help(.overview))
    }

    func testHelpForACommand() throws {
        XCTAssertEqual(try parse("help", "status"), .help(.status))
        XCTAssertEqual(try parse("help", "top"), .help(.top))
        XCTAssertEqual(try parse("help", "watch"), .help(.watch))
        XCTAssertEqual(try parse("help", "show"), .help(.show))
    }

    func testCommandHelpFlag() throws {
        XCTAssertEqual(try parse("status", "--help"), .help(.status))
        XCTAssertEqual(try parse("top", "-h"), .help(.top))
        XCTAssertEqual(try parse("watch", "--help"), .help(.watch))
        XCTAssertEqual(try parse("show", "-h"), .help(.show))
    }

    func testHelpWinsOverInvalidArguments() throws {
        XCTAssertEqual(try parse("top", "--limit", "abc", "--help"), .help(.top))
        XCTAssertEqual(try parse("watch", "--bogus", "-h"), .help(.watch))
    }

    func testVersionFlags() throws {
        XCTAssertEqual(try parse("--version"), .version)
        XCTAssertEqual(try parse("-v"), .version)
    }

    func testVersionRejectsExtraArguments() {
        XCTAssertEqual(usageError("--version", "status")?.message, "unexpected argument 'status'")
    }

    func testHelpRejectsUnknownTopicAndExtraArguments() {
        XCTAssertEqual(usageError("help", "bogus")?.message, "unknown command 'bogus'")
        XCTAssertEqual(usageError("help", "overview")?.message, "unknown command 'overview'")
        XCTAssertEqual(usageError("help", "top", "extra")?.message, "unexpected argument 'extra'")
    }

    func testUnknownCommand() {
        let error = usageError("stats")

        XCTAssertEqual(error?.message, "unknown command 'stats'")
        XCTAssertEqual(error?.topic, .overview)
    }

    func testUnknownTopLevelOption() {
        XCTAssertEqual(usageError("--json")?.message, "unknown option '--json'")
        XCTAssertEqual(usageError("--bogus")?.topic, .overview)
    }

    func testUnknownOptionsPerCommand() {
        XCTAssertEqual(usageError("status", "--limit", "3")?.message, "unknown option '--limit' for 'status'")
        XCTAssertEqual(usageError("top", "--verbose")?.message, "unknown option '--verbose' for 'top'")
        XCTAssertEqual(usageError("watch", "--json")?.message, "unknown option '--json' for 'watch'")
        XCTAssertEqual(usageError("watch", "-x")?.topic, .watch)
    }

    func testUnexpectedPositionalArguments() {
        XCTAssertEqual(usageError("status", "now")?.message, "unexpected argument 'now' for 'status'")
        XCTAssertEqual(usageError("top", "5")?.message, "unexpected argument '5' for 'top'")
    }

    func testMissingOptionValue() {
        XCTAssertEqual(usageError("top", "--limit")?.message, "option '--limit' requires a value")
        XCTAssertEqual(usageError("watch", "--interval")?.message, "option '--interval' requires a value")
        XCTAssertEqual(usageError("top", "--limit")?.topic, .top)
    }

    func testInvalidLimitValues() {
        for value in ["abc", "0", "-3", "2.5", "", "99999999999999999999", "1e2"] {
            let error = usageError("top", "--limit", value)
            XCTAssertEqual(
                error?.message,
                "invalid value '\(value)' for '--limit': expected a positive integer",
                "limit \(value)"
            )
            XCTAssertEqual(error?.topic, .top)
        }
    }

    func testInvalidIntervalValues() {
        for value in ["0", "-1", "abc", "nan", "inf", "0.1", "0.49", "3600.5", "1e9", ""] {
            XCTAssertEqual(
                usageError("watch", "--interval", value)?.message,
                "invalid value '\(value)' for '--interval': expected seconds between 0.5 and 3600",
                "interval \(value)"
            )
            XCTAssertNotNil(usageError("top", "--interval=\(value)"), "interval \(value)")
        }
    }

    func testIntervalBoundsAreInclusive() throws {
        XCTAssertEqual(try parse("watch", "--interval", "0.5"), .watch(WatchOptions(interval: 0.5)))
        XCTAssertEqual(try parse("watch", "--interval", "3600"), .watch(WatchOptions(interval: 3600)))
    }

    func testNegativeNumbersAreValuesNotFlags() {
        XCTAssertEqual(
            usageError("watch", "--interval", "-1")?.message,
            "invalid value '-1' for '--interval': expected seconds between 0.5 and 3600"
        )
    }

    func testBooleanFlagsRejectInlineValues() {
        XCTAssertEqual(usageError("status", "--json=true")?.message, "option '--json' does not take a value")
        XCTAssertEqual(usageError("top", "--json=1")?.topic, .top)
    }

    func testUsageErrorsNameTheCommandTheyBelongTo() {
        XCTAssertEqual(usageError("status", "--bogus")?.topic, .status)
        XCTAssertEqual(usageError("top", "--bogus")?.topic, .top)
        XCTAssertEqual(usageError("watch", "--bogus")?.topic, .watch)
        XCTAssertEqual(usageError("show", "--bogus")?.topic, .show)
    }
}
