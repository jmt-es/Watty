import AppKit
import SwiftUI
import WattyCore

@main
enum WattyLauncher {
    static func main() {
        if LaunchOptions.current.isCapturing {
            CaptureApp.main()
        } else {
            WattyApp.main()
        }
    }
}

struct WattyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var batteryModel: BatteryModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @ObservedObject private var notifications = NotificationService.shared
    @AppStorage(PreferenceKey.menuBarDisplay) private var menuBarDisplay: MenuBarDisplay = .percentage

    init() {
        if SingleInstanceGuard.anotherInstanceIsRunning() {
            exit(EXIT_SUCCESS)
        }

        let model = BatteryModel(
            historyStore: BatteryHistoryStore(),
            alertCoordinator: BatteryAlertCoordinator()
        )
        _batteryModel = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(surface: .menuBar)
                .environmentObject(batteryModel)
        } label: {
            MenuBarLabel(model: batteryModel, display: menuBarDisplay)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show Watty") {
                    AppDelegate.shared?.showPanel()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        SettingsScene(model: batteryModel, launchAtLogin: launchAtLogin, notifications: notifications)
    }
}

struct CaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var batteryModel: BatteryModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @ObservedObject private var notifications = NotificationService.shared

    init() {
        let options = LaunchOptions.current
        let model: BatteryModel
        if let scenario = options.demoScenario {
            model = DemoSession.makeModel(for: scenario)
        } else {
            let historyStore = BatteryHistoryStore(
                fileURL: options.historyFileURL ?? BatteryHistoryStore.defaultFileURL,
                writesEnabled: false
            )
            model = BatteryModel(historyStore: historyStore)
        }
        _batteryModel = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        SettingsScene(model: batteryModel, launchAtLogin: launchAtLogin, notifications: notifications)
    }
}

struct SettingsScene: Scene {
    let model: BatteryModel
    let launchAtLogin: LaunchAtLoginController
    let notifications: NotificationService

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(launchAtLogin)
                .environmentObject(notifications)
        }
    }
}
