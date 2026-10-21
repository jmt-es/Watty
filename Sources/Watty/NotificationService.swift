import AppKit
import Foundation
import os
import UserNotifications
import WattyCore

enum NotificationPermission: Equatable {
    case unsupported
    case notDetermined
    case allowed
    case denied
}

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    static var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    @Published private(set) var permission: NotificationPermission
    @Published private(set) var errorMessage: String?

    private let logger = AppLog.logger("notifications")
    private let responseDelegate = NotificationResponseDelegate()

    private init() {
        permission = Self.isSupported ? .notDetermined : .unsupported
    }

    private var center: UNUserNotificationCenter? {
        Self.isSupported ? UNUserNotificationCenter.current() : nil
    }

    func activate() {
        guard let center else {
            logger.info("notifications unavailable outside an app bundle")
            return
        }
        center.delegate = responseDelegate
        Task { await refreshPermission() }
    }

    func refreshPermission() async {
        guard let center else {
            permission = .unsupported
            return
        }
        let settings = await center.notificationSettings()
        permission = Self.permission(for: settings.authorizationStatus)
    }

    func requestPermissionIfNeeded() async {
        await refreshPermission()
        guard permission == .notDetermined, let center else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            errorMessage = nil
            logger.info("notification authorization \(granted ? "granted" : "declined", privacy: .public)")
        } catch {
            errorMessage = String(localized: "Couldn't ask for notification permission.")
            logger.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshPermission()
    }

    func deliver(_ alert: BatteryAlert) async {
        await refreshPermission()
        guard permission == .allowed, let center else {
            logger.info("alert \(alert.identifier, privacy: .public) not delivered, permission \(String(describing: self.permission), privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
            logger.info("delivered alert \(alert.identifier, privacy: .public) at \(alert.level)%")
        } catch {
            logger.error("alert \(alert.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate), NSWorkspace.shared.open(url) else { continue }
            return
        }
        logger.error("could not open notification settings")
    }

    private static func permission(for status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

private final class NotificationResponseDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { _ = AppDelegate.shared?.showPanel() }
    }
}

extension BatteryAlert {
    var identifier: String {
        "\(WattyVersion.bundleIdentifier).alert.\(kind.identifierSuffix)"
    }

    var title: String {
        switch kind {
        case .lowBattery: return String(localized: "Battery low")
        case .chargeLimit: return String(localized: "Charge limit reached")
        case .fullyCharged: return String(localized: "Battery fully charged")
        }
    }

    var message: String {
        let percent = ValueFormat.percent(level)
        switch kind {
        case .lowBattery: return String(localized: "The battery is at \(percent). Plug in your charger.")
        case .chargeLimit: return String(localized: "The battery reached \(percent). Unplug to go easy on its health.")
        case .fullyCharged: return String(localized: "The battery is full. You can unplug your charger.")
        }
    }
}

private extension BatteryAlertKind {
    var identifierSuffix: String {
        switch self {
        case .lowBattery: return "lowBattery"
        case .chargeLimit: return "chargeLimit"
        case .fullyCharged: return "fullyCharged"
        }
    }
}
