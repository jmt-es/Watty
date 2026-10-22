import Foundation

struct LevelPivot: Equatable, Sendable {
    let index: Int
    let isPeak: Bool
}

enum LevelSwings {
    private enum Leg {
        case unknown
        case rising
        case falling
    }

    static func pivots(in levels: [Double], minimumSwing: Double) -> [LevelPivot] {
        guard levels.count > 1 else { return [] }

        var pivots: [LevelPivot] = []
        var leg = Leg.unknown
        var high = 0
        var low = 0

        for index in 1..<levels.count {
            let level = levels[index]
            switch leg {
            case .unknown:
                if level >= levels[high] { high = index }
                if level < levels[low] { low = index }
                if levels[high] - level >= minimumSwing {
                    pivots.append(LevelPivot(index: high, isPeak: true))
                    leg = .falling
                    low = index
                } else if level - levels[low] >= minimumSwing {
                    pivots.append(LevelPivot(index: low, isPeak: false))
                    leg = .rising
                    high = index
                }
            case .rising:
                if level >= levels[high] {
                    high = index
                } else if levels[high] - level >= minimumSwing {
                    pivots.append(LevelPivot(index: high, isPeak: true))
                    leg = .falling
                    low = index
                }
            case .falling:
                if level < levels[low] {
                    low = index
                } else if level - levels[low] >= minimumSwing {
                    pivots.append(LevelPivot(index: low, isPeak: false))
                    leg = .rising
                    high = index
                }
            }
        }

        switch leg {
        case .rising: pivots.append(LevelPivot(index: high, isPeak: true))
        case .falling: pivots.append(LevelPivot(index: low, isPeak: false))
        case .unknown: break
        }
        return pivots
    }
}
