import Foundation

public struct PowerAccumulation: Equatable, Sendable {
    public let milliwattTicks: Int64
    public let ticks: Int64

    public init(milliwattTicks: Int64, ticks: Int64) {
        self.milliwattTicks = milliwattTicks
        self.ticks = ticks
    }
}
