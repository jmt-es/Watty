import XCTest
@testable import WattyCore

final class TemperatureReaderTests: XCTestCase {
    private final class Clock {
        var uptime: TimeInterval = 1_000
    }

    private final class Counter {
        var value = 0
    }

    private func dieSensors() -> TemperatureReader.SensorConnection {
        TemperatureReader.SensorConnection {
            [(name: "PMU tdie1", celsius: 60), (name: "PMU tdie2", celsius: 50), (name: "NAND CH0 temp", celsius: 40)]
        }
    }

    func testMissingSensorsAreNotProbedAgainBeforeTheRetryInterval() {
        let clock = Clock()
        let attempts = Counter()
        let reader = TemperatureReader(
            connect: { attempts.value += 1; return nil },
            uptime: { clock.uptime }
        )

        for _ in 0..<10 { XCTAssertNil(reader.read()) }
        XCTAssertEqual(attempts.value, 1)

        clock.uptime += TemperatureReader.missingSensorsRetryInterval - 1
        XCTAssertNil(reader.read())
        XCTAssertEqual(attempts.value, 1)

        clock.uptime += 2
        XCTAssertNil(reader.read())
        XCTAssertEqual(attempts.value, 2)
        XCTAssertNil(reader.read())
        XCTAssertEqual(attempts.value, 2)
    }

    func testNegativeResultReturnsImmediatelyEvenWhenProbingIsSlow() {
        let clock = Clock()
        let reader = TemperatureReader(
            connect: { Thread.sleep(forTimeInterval: 0.2); return nil },
            uptime: { clock.uptime }
        )
        XCTAssertNil(reader.read())

        let startedAt = Date()
        for _ in 0..<50 { XCTAssertNil(reader.read()) }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.1)
    }

    func testConnectedSensorsAreReusedWithoutReconnecting() throws {
        let clock = Clock()
        let attempts = Counter()
        let reader = TemperatureReader(
            connect: { attempts.value += 1; return self.dieSensors() },
            uptime: { clock.uptime }
        )

        for _ in 0..<5 {
            let readings = try XCTUnwrap(reader.read())
            XCTAssertEqual(readings.socMaxCelsius, 60)
            XCTAssertEqual(try XCTUnwrap(readings.socAverageCelsius), 55, accuracy: 0.001)
            XCTAssertEqual(readings.sensorCount, 2)
        }

        XCTAssertEqual(attempts.value, 1)
    }

    func testRecoversWhenSensorsAppearAfterTheRetryInterval() throws {
        let clock = Clock()
        let sensorsAvailable = Counter()
        let reader = TemperatureReader(
            connect: { sensorsAvailable.value == 1 ? self.dieSensors() : nil },
            uptime: { clock.uptime }
        )
        XCTAssertNil(reader.read())

        sensorsAvailable.value = 1
        XCTAssertNil(reader.read())

        clock.uptime += TemperatureReader.missingSensorsRetryInterval + 1
        XCTAssertEqual(try XCTUnwrap(reader.read()).socMaxCelsius, 60)
    }

    func testRetryIntervalIsAFewMinutes() {
        XCTAssertGreaterThanOrEqual(TemperatureReader.missingSensorsRetryInterval, 60)
        XCTAssertLessThanOrEqual(TemperatureReader.missingSensorsRetryInterval, 600)
    }

    func testLiveReaderNeverCrashesAndStaysFast() {
        let reader = TemperatureReader()
        let startedAt = Date()

        for _ in 0..<20 { _ = reader.read() }

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }
}
