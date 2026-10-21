import XCTest
@testable import WattyCLI

final class HelpTextTests: XCTestCase {
    func testEveryTopicFitsIn80Columns() {
        for topic in HelpTopic.allCases {
            for line in HelpText.text(for: topic, version: "9.9.9").split(separator: "\n") {
                XCTAssertLessThanOrEqual(line.count, 80, "\(topic): \(line)")
            }
        }
    }

    func testEveryTopicStartsWithItsUsageLine() {
        for topic in HelpTopic.allCases where topic != .overview {
            let text = HelpText.text(for: topic, version: "9.9.9")

            XCTAssertTrue(text.hasPrefix("Usage: \(HelpText.usageLine(for: topic))\n"), "\(topic)")
        }
    }

    func testOverviewListsEveryCommandAndTheExitCodes() {
        let text = HelpText.text(for: .overview, version: "9.9.9")

        XCTAssertTrue(text.hasPrefix("Watty 9.9.9 - "))
        for command in ["status", "top", "watch", "show", "help"] {
            XCTAssertTrue(text.contains("  \(command) "), command)
        }
        XCTAssertTrue(text.contains("--version"))
        XCTAssertTrue(text.contains("64 usage error"))
    }

    func testOptionHelpMatchesTheParserDefaults() {
        let top = HelpText.text(for: .top, version: "9.9.9")
        let watch = HelpText.text(for: .watch, version: "9.9.9")

        XCTAssertTrue(top.contains("(default 10)"))
        XCTAssertTrue(top.contains("0.5 to 3600 (default 1)"))
        XCTAssertTrue(watch.contains("0.5 to 3600 (default 2)"))
    }

    func testEveryFlagInAUsageLineIsAcceptedByTheParser() {
        let sampleValues = ["--limit": "3", "--interval": "1"]

        for topic in HelpTopic.allCases where topic != .overview {
            let flags = HelpText.usageLine(for: topic)
                .split(separator: " ")
                .filter { $0.hasPrefix("[--") }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
            for flag in flags {
                let arguments = [topic.rawValue, flag] + (sampleValues[flag].map { [$0] } ?? [])

                XCTAssertNoThrow(try CommandParser.parse(arguments), "\(arguments)")
            }
        }
    }

    func testUsageErrorTextHasMessageUsageAndHint() {
        let error = UsageError("unknown option '--bogus' for 'top'", topic: .top)

        XCTAssertEqual(HelpText.usageErrorText(for: error), """
        watty: unknown option '--bogus' for 'top'
        usage: watty top [--json] [--limit N] [--interval SECONDS]
        Try 'watty top --help' for more information.

        """)
    }

    func testUsageErrorForTheOverviewPointsAtGeneralHelp() {
        let text = HelpText.usageErrorText(for: UsageError("unknown command 'foo'", topic: .overview))

        XCTAssertTrue(text.contains("usage: watty [status|top|watch|show|help] [options]"))
        XCTAssertTrue(text.contains("Try 'watty --help' for more information."))
    }

    func testHelpTextEndsWithASingleNewline() {
        for topic in HelpTopic.allCases {
            let text = HelpText.text(for: topic, version: "9.9.9")

            XCTAssertTrue(text.hasSuffix("\n"), "\(topic)")
            XCTAssertFalse(text.hasSuffix("\n\n"), "\(topic)")
        }
    }
}
