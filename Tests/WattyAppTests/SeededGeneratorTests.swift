import XCTest
@testable import Watty

final class SeededGeneratorTests: XCTestCase {
    func testMatchesTheSplitMix64ReferenceSequence() {
        var generator = SeededGenerator(seed: 1_234_567)

        let sequence = (0..<5).map { _ in generator.next() }

        XCTAssertEqual(sequence, [
            6_457_827_717_110_365_317,
            3_203_168_211_198_807_973,
            9_817_491_932_198_370_423,
            4_593_380_528_125_082_431,
            16_408_922_859_458_223_821
        ])
    }

    func testTheSameSeedRepeatsAndAnotherSeedDiffers() {
        var first = SeededGenerator(seed: 5)
        var repeated = SeededGenerator(seed: 5)
        var other = SeededGenerator(seed: 6)

        let sequence = (0..<8).map { _ in first.next() }

        XCTAssertEqual(sequence, (0..<8).map { _ in repeated.next() })
        XCTAssertNotEqual(sequence, (0..<8).map { _ in other.next() })
    }

    func testUnitValuesStayInTheHalfOpenUnitInterval() {
        var generator = SeededGenerator(seed: 7)

        for _ in 0..<1_000 {
            let value = generator.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }
}
