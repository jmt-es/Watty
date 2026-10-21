import Foundation

struct DemoSignal {
    private struct Wave {
        let cyclesPerWindow: Double
        let phase: Double
        let weight: Double
    }

    private let waves: [Wave]
    private let totalWeight: Double
    private let window: TimeInterval

    init(seed: UInt64, cyclesPerWindow: [Double], window: TimeInterval = RefreshCadence.statsWindow) {
        var generator = SeededGenerator(seed: seed)
        waves = cyclesPerWindow.enumerated().map { index, cycles in
            Wave(cyclesPerWindow: cycles, phase: generator.nextUnit() * 2 * .pi, weight: 1 / Double(index + 1))
        }
        totalWeight = waves.reduce(0) { $0 + $1.weight }
        self.window = window
    }

    func deviation(secondsAgo: TimeInterval) -> Double {
        level(secondsAgo: secondsAgo) - level(secondsAgo: 0)
    }

    private func level(secondsAgo: TimeInterval) -> Double {
        let turns = -secondsAgo / window
        let sum = waves.reduce(0) { total, wave in
            total + wave.weight * sin(2 * .pi * wave.cyclesPerWindow * turns + wave.phase)
        }
        return sum / totalWeight
    }
}
