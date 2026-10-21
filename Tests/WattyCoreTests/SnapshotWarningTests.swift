import XCTest
@testable import WattyCore

final class SnapshotWarningTests: XCTestCase {
    func testMessagesKeepTheEnglishTextScriptsAndTheJSONReportSee() {
        XCTAssertEqual(SnapshotWarning.powerSourceReadFailed.message, "IOKit power source read failed")
        XCTAssertEqual(SnapshotWarning.smartBatteryReadFailed.message, "AppleSmartBattery read failed")
        XCTAssertEqual(SnapshotWarning.ioregBatteryReadFailed.message, "ioreg battery read failed")
        XCTAssertEqual(SnapshotWarning.pmsetBatteryReadFailed.message, "pmset battery read failed")
        XCTAssertEqual(SnapshotWarning.pmsetSettingsReadFailed.message, "pmset settings read failed")
        XCTAssertEqual(SnapshotWarning.systemProfilerDetailReadFailed.message, "system_profiler detail read failed")
    }

    func testEveryMessageIsUniqueAndMapsBackToItsCase() {
        let messages = SnapshotWarning.allCases.map(\.message)

        XCTAssertEqual(Set(messages).count, SnapshotWarning.allCases.count)
        for warning in SnapshotWarning.allCases {
            XCTAssertEqual(SnapshotWarning(rawValue: warning.message), warning)
        }
    }

    func testUnknownMessagesAreNotWarnings() {
        XCTAssertNil(SnapshotWarning(rawValue: "something else failed"))
    }
}
