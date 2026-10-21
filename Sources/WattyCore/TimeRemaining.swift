import Foundation

public enum TimeRemaining: Equatable {
    case untilFull(minutes: Int)
    case finishingCharge
    case calculatingUntilFull
    case fullyCharged
    case runningFromAdapter
    case untilEmpty(minutes: Int)
    case calculatingUntilEmpty
    case waitingForFirstReading

    public var text: String {
        switch self {
        case .untilFull(let minutes): return "\(BatterySnapshot.clockText(minutes: minutes)) to full"
        case .finishingCharge: return "Finishing charge"
        case .calculatingUntilFull: return "Calculating time to full"
        case .fullyCharged: return "Fully charged"
        case .runningFromAdapter: return "Running from adapter"
        case .untilEmpty(let minutes): return "\(BatterySnapshot.clockText(minutes: minutes)) left"
        case .calculatingUntilEmpty: return "Calculating time left"
        case .waitingForFirstReading: return "Waiting for first reading"
        }
    }
}

extension BatterySnapshot {
    public var timeRemaining: TimeRemaining {
        switch chargeState {
        case .charging:
            if let minutes = timeToFullMinutes { return .untilFull(minutes: minutes) }
            return isFinishingCharge || level >= 100 ? .finishingCharge : .calculatingUntilFull
        case .charged:
            return .fullyCharged
        case .pluggedInNotCharging:
            return .runningFromAdapter
        case .onBattery:
            guard let minutes = timeToEmptyMinutes else { return .calculatingUntilEmpty }
            return .untilEmpty(minutes: minutes)
        case .unknown:
            return .waitingForFirstReading
        }
    }
}
