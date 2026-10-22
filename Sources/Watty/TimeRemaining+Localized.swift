import Foundation
import WattyCore

extension TimeRemaining {
    var localizedText: String {
        switch self {
        case .untilFull(let minutes):
            return String(localized: "\(BatterySnapshot.clockText(minutes: minutes)) to full")
        case .finishingCharge:
            return String(localized: "Finishing charge")
        case .calculatingUntilFull:
            return String(localized: "Calculating time to full")
        case .fullyCharged:
            return String(localized: "Fully charged")
        case .runningFromAdapter:
            return String(localized: "Running from adapter")
        case .adapterCannotKeepUp(let ratedWatts):
            guard let ratedWatts else { return String(localized: "The adapter can't keep up") }
            return String(localized: "The \(ratedWatts) W adapter can't keep up")
        case .usingBatteryOnAdapter:
            return String(localized: "Using the battery while plugged in")
        case .untilEmpty(let minutes):
            return String(localized: "\(BatterySnapshot.clockText(minutes: minutes)) left")
        case .calculatingUntilEmpty:
            return String(localized: "Calculating time left")
        case .waitingForFirstReading:
            return String(localized: "Waiting for first reading")
        }
    }
}
