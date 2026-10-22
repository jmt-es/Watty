import Foundation

public enum NetFlow: String, Equatable, Sendable {
    case charging
    case draining
    case holding
}

public struct NetFlowEstimate: Equatable, Sendable {
    public let flow: NetFlow?
    public let averageBatteryWatts: Double?
    public let levelTrendPointsPerMinute: Double?

    public init(flow: NetFlow?, averageBatteryWatts: Double? = nil, levelTrendPointsPerMinute: Double? = nil) {
        self.flow = flow
        self.averageBatteryWatts = averageBatteryWatts
        self.levelTrendPointsPerMinute = levelTrendPointsPerMinute
    }

    public static let unknown = NetFlowEstimate(flow: nil)
}
