struct SeededGenerator: RandomNumberGenerator {
    private enum SplitMix64 {
        static let increment: UInt64 = 0x9E37_79B9_7F4A_7C15
        static let firstMultiplier: UInt64 = 0xBF58_476D_1CE4_E5B9
        static let secondMultiplier: UInt64 = 0x94D0_49BB_1331_11EB
        static let firstShift: UInt64 = 30
        static let secondShift: UInt64 = 27
        static let finalShift: UInt64 = 31
    }

    private static let unitMantissaBits = 53
    private static let unitDivisor = Double(UInt64(1) << UInt64(unitMantissaBits))

    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= SplitMix64.increment
        var mixed = state
        mixed = (mixed ^ (mixed >> SplitMix64.firstShift)) &* SplitMix64.firstMultiplier
        mixed = (mixed ^ (mixed >> SplitMix64.secondShift)) &* SplitMix64.secondMultiplier
        return mixed ^ (mixed >> SplitMix64.finalShift)
    }

    mutating func nextUnit() -> Double {
        let mantissa = next() >> UInt64(UInt64.bitWidth - Self.unitMantissaBits)
        return Double(mantissa) / Self.unitDivisor
    }
}
