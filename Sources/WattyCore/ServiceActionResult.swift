import Foundation

public enum ServiceActionReason: Equatable {
    case applied(PowerMode)
    case systemKeptMode(PowerMode)
    case canceled
    case timedOut
    case failed(detail: String?)

    public var isSuccess: Bool {
        if case .applied = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .applied(let mode): return "\(mode.longTitle) applied"
        case .systemKeptMode(let mode): return "System kept \(mode.longTitle)"
        case .canceled: return "Authorization canceled"
        case .timedOut: return "Authorization timed out"
        case .failed(let detail): return detail ?? "Power mode update failed"
        }
    }
}

public struct ServiceActionResult: Equatable {
    public let reason: ServiceActionReason
    public let resultingMode: PowerMode?

    public init(reason: ServiceActionReason, resultingMode: PowerMode? = nil) {
        self.reason = reason
        self.resultingMode = resultingMode
    }

    public var success: Bool {
        reason.isSuccess
    }

    public var message: String {
        reason.message
    }
}
