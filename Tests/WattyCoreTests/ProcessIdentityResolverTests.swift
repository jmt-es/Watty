import XCTest
@testable import WattyCore

final class ProcessIdentityResolverTests: XCTestCase {
    private static let unusedPid = Int(Int32.max)

    func testFindsOutermostAppBundle() {
        let helper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

        XCTAssertEqual(ProcessIdentityResolver.outermostAppBundle(in: helper), "/Applications/Google Chrome.app")
        XCTAssertNil(ProcessIdentityResolver.outermostAppBundle(in: "/usr/bin/top"))
        XCTAssertEqual(ProcessIdentityResolver.outermostAppBundle(in: "/Applications/Safari.app"), "/Applications/Safari.app")
    }

    func testResolvesOwnProcess() {
        let identity = ProcessIdentityResolver.resolve(pid: Int(ProcessInfo.processInfo.processIdentifier), command: "xctest")

        XCTAssertFalse(identity.name.isEmpty)
        XCTAssertFalse(identity.key.isEmpty)
    }

    func testGroupsHelpersWithTheirAppByBundleWithoutNameRules() {
        let main = ProcessIdentityResolver.resolve(
            pid: Self.unusedPid,
            command: "WattyFixture",
            knownPath: "/Applications/WattyFixture.app/Contents/MacOS/WattyFixture"
        )
        let helper = ProcessIdentityResolver.resolve(
            pid: Self.unusedPid,
            command: "WattyFixture Helper (Renderer)",
            knownPath: "/Applications/WattyFixture.app/Contents/Frameworks/WattyFixture Helper (Renderer).app/Contents/MacOS/WattyFixture Helper (Renderer)"
        )

        XCTAssertEqual(main.key, helper.key)
        XCTAssertEqual(main.name, "WattyFixture")
        XCTAssertEqual(helper.name, "WattyFixture")
    }

    func testAppsWhoseNamesStartLikeOtherAppsKeepTheirOwnIdentity() {
        for name in ["CodeSample", "ClaudeSample", "CursorSample", "SafariSample", "FirefoxSample"] {
            let identity = ProcessIdentityResolver.resolve(
                pid: Self.unusedPid,
                command: name,
                knownPath: "/Applications/\(name).app/Contents/MacOS/\(name)"
            )

            XCTAssertEqual(identity.name, name)
            XCTAssertEqual(identity.key, "/Applications/\(name).app")
        }
    }

    func testProcessesOutsideBundlesUseTheirExecutableNameAndPathAsKey() {
        let identity = ProcessIdentityResolver.resolve(
            pid: Self.unusedPid,
            command: "MTLCompilerService",
            knownPath: "/System/Library/PrivateFrameworks/MTLCompiler.framework/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService"
        )

        XCTAssertEqual(identity.name, "Metal Compiler")
        XCTAssertEqual(identity.key, "/System/Library/PrivateFrameworks/MTLCompiler.framework/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService")
    }

    func testNormalizedNameStripsGenericHelperFragments() {
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Google Chrome Helper (Renderer)"), "Google Chrome")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Example Helper (GPU)"), "Example")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Example Helper (Plugin)"), "Example")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Example Helper"), "Example")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Example (Service)"), "Example")
    }

    func testNormalizedNameDoesNotRewriteNamesByApplicationPrefix() {
        for name in ["Claude", "Codex", "Cursor", "Code", "CodeSigningHelper", "CodeSample", "Safari", "Firefox", "Google Chrome"] {
            XCTAssertEqual(TelemetryParsers.normalizedProcessName(name), name)
        }
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Code Helper (Plugin)"), "Code")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("Cursor Helper (Renderer)"), "Cursor")
    }

    func testNormalizedNameKeepsCasesForProcessesThatLiveOutsideAppBundles() {
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("MTLCompilerService"), "Metal Compiler")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("com.apple.WebKit.WebContent"), "Safari Web Content")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName("com.apple.WebKit.Networking"), "Safari Web Content")
    }

    func testNormalizedNameNeverCollapsesToAnEmptyName() {
        XCTAssertEqual(TelemetryParsers.normalizedProcessName(" Helper"), "Helper")
        XCTAssertEqual(TelemetryParsers.normalizedProcessName(""), "")
    }
}
