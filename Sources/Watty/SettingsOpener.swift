import AppKit
import SwiftUI

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
    private static let verificationDelay: Duration = .milliseconds(400)

    private let logger = AppLog.logger("settings")
    private var openAction: (() -> Void)?

    static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == settingsWindowIdentifier }
    }

    func register(_ action: @escaping () -> Void) {
        openAction = action
    }

    func open() {
        AppActivation.bringToFront()
        if let openAction {
            openAction()
        } else {
            sendLegacyAction()
        }

        Task {
            try? await Task.sleep(for: Self.verificationDelay)
            ensureVisible()
        }
    }

    private func ensureVisible() {
        if let window = Self.settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        logger.error("settings window did not appear, retrying with the legacy action")
        sendLegacyAction()
    }

    private func sendLegacyAction() {
        let selectorName: String
        if #available(macOS 14.0, *) {
            selectorName = "showSettingsWindow:"
        } else {
            selectorName = "showPreferencesWindow:"
        }
        let handled = NSApp.sendAction(Selector(selectorName), to: nil, from: nil)
        if !handled {
            logger.error("no responder handled \(selectorName, privacy: .public)")
        }
    }
}

// openSettings only exists in a scene's environment, so the menu bar popover hands it to SettingsOpener.
struct SettingsActionRegistrar: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernRegistrar()
        }
    }

    @available(macOS 14.0, *)
    private struct ModernRegistrar: View {
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    SettingsOpener.shared.register { openSettings() }
                }
        }
    }
}
