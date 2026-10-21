import XCTest
@testable import Watty

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    private func mode(_ path: String, bundleIdentifier: String? = "com.jmtes.watty") -> LaunchAtLoginController.Mode {
        LaunchAtLoginController.mode(forBundleURL: URL(fileURLWithPath: path), bundleIdentifier: bundleIdentifier)
    }

    func testHomebrewCellarInstallsAreManagedByHomebrew() {
        XCTAssertEqual(mode("/opt/homebrew/Cellar/watty/1.3.0/Watty.app"), .homebrew)
        XCTAssertEqual(mode("/usr/local/Cellar/watty/1.3.0/Watty.app"), .homebrew)
    }

    func testHomebrewServiceLaunchThroughTheOptLinkIsManagedByHomebrew() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keg = root.appendingPathComponent("Cellar/watty/1.3.0")
        try FileManager.default.createDirectory(at: keg.appendingPathComponent("Watty.app"), withIntermediateDirectories: true)
        let optDirectory = root.appendingPathComponent("opt")
        try FileManager.default.createDirectory(at: optDirectory, withIntermediateDirectories: true)
        let optLink = optDirectory.appendingPathComponent("watty")
        try FileManager.default.createSymbolicLink(atPath: optLink.path, withDestinationPath: "../Cellar/watty/1.3.0")

        XCTAssertEqual(mode(optLink.appendingPathComponent("Watty.app").path), .homebrew)
    }

    func testRegularAppBundlesRegisterThemselves() {
        XCTAssertEqual(mode("/Applications/Watty.app"), .system)
        XCTAssertEqual(mode("/Users/someone/Applications/Watty.app"), .system)
        XCTAssertEqual(mode("/opt/homebrew/Caskroom/watty/1.3.0/Watty.app"), .system)
    }

    func testBareExecutablesCannotRegister() {
        XCTAssertEqual(mode("/Users/someone/Code/Watty/.build/debug/Watty"), .unavailable)
        XCTAssertEqual(mode("/Applications/Watty.app", bundleIdentifier: nil), .unavailable)
    }
}
