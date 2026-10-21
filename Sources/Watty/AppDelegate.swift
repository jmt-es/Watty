import AppKit
import SwiftUI
import WattyCore

enum SingleInstanceGuard {
    static func anotherInstanceIsRunning() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? WattyVersion.bundleIdentifier
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentPID }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    static var model: BatteryModel?

    private static let showPanelNotification = Notification.Name("com.jmtes.watty.show")
    private static let terminationSignals = [SIGTERM, SIGINT]

    private var panelWindow: NSWindow?
    private var panelIsVisible = false
    private var captureController: CaptureController?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        let options = LaunchOptions.current

        if let appearance = options.appearance {
            NSApp.appearance = appearance.nsAppearance
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelNotification(_:)),
            name: Self.showPanelNotification,
            object: nil
        )

        if let capture = options.capture {
            startCapture(capture)
        } else {
            NotificationService.shared.activate()
            installTerminationHandlers()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.model?.persistHistory()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        showPanel()
    }

    @objc private func showPanelNotification(_ notification: Notification) {
        showPanel()
    }

    @objc private func panelWillClose(_ notification: Notification) {
        guard panelIsVisible else { return }
        panelIsVisible = false
        Self.model?.surfaceDidDisappear()
    }

    @discardableResult
    func showPanel() -> NSWindow? {
        guard let model = Self.model else { return nil }

        if panelWindow == nil {
            let rootView = ContentView(surface: .panel)
                .environmentObject(model)
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.title = "Watty"
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(panelWillClose(_:)),
                name: NSWindow.willCloseNotification,
                object: window
            )
            panelWindow = window
        }

        if !panelIsVisible {
            panelIsVisible = true
            model.surfaceDidAppear()
        }
        AppActivation.bringToFront()
        panelWindow?.makeKeyAndOrderFront(nil)
        return panelWindow
    }

    private func startCapture(_ capture: LaunchOptions.Capture) {
        guard let model = Self.model else {
            FileHandle.standardError.write(Data("watty: capture failed: the battery model did not start\n".utf8))
            exit(CaptureController.failureExitCode)
        }
        captureController = CaptureController(capture: capture, model: model)
        captureController?.start()
    }

    private func installTerminationHandlers() {
        for signalNumber in Self.terminationSignals {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
