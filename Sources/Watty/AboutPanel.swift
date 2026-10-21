import AppKit
import WattyCore

@MainActor
enum AboutPanel {
    private static let creditsFontSize: CGFloat = 11

    static func show() {
        AppActivation.bringToFront()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Watty",
            .applicationVersion: WattyVersion.current,
            .version: WattyVersion.build,
            .credits: credits
        ])
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = String(localized: "Battery, charger and power telemetry for your menu bar.\nOpen source under the MIT License.")
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: creditsFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ])
    }
}

enum AppActivation {
    @MainActor
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
