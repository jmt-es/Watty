import Foundation
import WattyCore

@MainActor
final class BatteryAlertCoordinator {
    private var evaluator = BatteryAlertEvaluator()
    private let notifications: NotificationService
    private let defaults: UserDefaults

    init(notifications: NotificationService? = nil, defaults: UserDefaults = .standard) {
        self.notifications = notifications ?? .shared
        self.defaults = defaults
    }

    func snapshotDidUpdate(_ snapshot: BatterySnapshot) {
        guard snapshot.hasBattery, !snapshot.isEmpty else { return }

        let configuration = Preferences.alertConfiguration(from: defaults)
        let alerts = evaluator.evaluate(
            level: snapshot.level,
            chargeState: snapshot.chargeState,
            configuration: configuration
        )
        for alert in alerts {
            Task { await notifications.deliver(alert) }
        }
    }
}
