import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    enum Mode: Equatable {
        case system
        case homebrew
        case unavailable
    }

    static let homebrewStartCommand = "brew services start watty"
    private static let homebrewCellarMarker = "/Cellar/"

    let mode: Mode

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    private let logger = AppLog.logger("login-item")

    init(bundleURL: URL = Bundle.main.bundleURL, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        mode = Self.mode(forBundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
        status = SMAppService.mainApp.status
    }

    static func mode(forBundleURL bundleURL: URL, bundleIdentifier: String?) -> Mode {
        if bundleURL.resolvingSymlinksInPath().path.contains(homebrewCellarMarker) { return .homebrew }
        if bundleURL.pathExtension != "app" || bundleIdentifier == nil { return .unavailable }
        return .system
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        guard mode == .system else { return }
        errorMessage = nil

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("launch at login \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            logger.error("launch at login \(enabled ? "enable" : "disable", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = enabled
                ? String(localized: "Couldn't turn on launch at login: \(error.localizedDescription)")
                : String(localized: "Couldn't turn off launch at login: \(error.localizedDescription)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
