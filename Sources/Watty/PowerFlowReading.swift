import Foundation
import WattyCore

struct PowerFlowReading: Equatable {
    enum BatteryDirection: Equatable {
        case charging
        case discharging
        case draining
        case idle
    }

    static let flowThresholdWatts = 0.4
    static let adapterFlowThresholdWatts = 0.5

    let onAdapter: Bool
    let adapterInputWatts: Double?
    let adapterRatedWatts: Int?
    let systemLoadWatts: Double?
    let batteryWatts: Double?
    let batteryDirection: BatteryDirection

    var adapterIsFeedingSystem: Bool {
        onAdapter && (adapterInputWatts ?? 0) > Self.adapterFlowThresholdWatts
    }

    init(snapshot: BatterySnapshot) {
        let onAdapter = snapshot.powerSource == .adapter
        let isDrainingOnAdapter = snapshot.isDrainingOnAdapter
        let batteryWatts = isDrainingOnAdapter ? snapshot.netFlow.averageBatteryWatts : snapshot.batteryPowerWatts

        self.onAdapter = onAdapter
        adapterInputWatts = snapshot.systemPowerWatts
        adapterRatedWatts = snapshot.adapterRatedWatts
        self.batteryWatts = batteryWatts
        systemLoadWatts = Self.systemLoad(snapshot: snapshot, onAdapter: onAdapter, batteryWatts: batteryWatts)

        let watts = batteryWatts ?? 0
        if isDrainingOnAdapter {
            batteryDirection = .draining
        } else if watts > Self.flowThresholdWatts {
            batteryDirection = .charging
        } else if watts < -Self.flowThresholdWatts {
            batteryDirection = .discharging
        } else {
            batteryDirection = .idle
        }
    }

    private static func systemLoad(snapshot: BatterySnapshot, onAdapter: Bool, batteryWatts: Double?) -> Double? {
        if let load = snapshot.systemLoadWatts { return load }
        let battery = batteryWatts ?? 0
        if onAdapter, let input = snapshot.systemPowerWatts {
            return max(0, input - battery)
        }
        return battery < 0 ? -battery : nil
    }
}
