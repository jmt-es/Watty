import XCTest
@testable import WattyCore

final class SystemStatsTests: XCTestCase {
    private static let cpuSamplingInterval: TimeInterval = 0.25
    private static let maximumCPUSamplingAttempts = 20

    func testCPUUsageFromTickDeltas() throws {
        let previous = CPUTicks(user: 100, system: 50, idle: 800, nice: 0)
        let current = CPUTicks(user: 130, system: 60, idle: 850, nice: 10)

        let usage = try XCTUnwrap(CPUUsage.between(previous, current))

        XCTAssertEqual(usage.userPercent, 40, accuracy: 0.001)
        XCTAssertEqual(usage.systemPercent, 10, accuracy: 0.001)
        XCTAssertEqual(usage.totalPercent, 50, accuracy: 0.001)
        XCTAssertNil(CPUUsage.between(current, current))
    }

    func testMemoryUsedMatchesActivityMonitorFormula() {
        let usage = MemoryUsage.from(
            internalPages: 1_000,
            purgeablePages: 100,
            wiredPages: 200,
            compressorPages: 300,
            pageSize: 16_384,
            totalBytes: 64 * 1_073_741_824,
            swapUsedBytes: 0
        )

        XCTAssertEqual(usage.appBytes, 900 * 16_384)
        XCTAssertEqual(usage.usedBytes, 1_400 * 16_384)
        XCTAssertEqual(usage.usedPercent, Double(1_400 * 16_384) / Double(64 * 1_073_741_824) * 100, accuracy: 0.0001)
    }

    func testTemperatureSummaryIgnoresBogusSensors() {
        let readings = TemperatureReadings.summarize([
            (name: "PMU tdie1", celsius: 66.4),
            (name: "PMU tdie2", celsius: 58.6),
            (name: "PMU tdev1", celsius: -9202.9),
            (name: "gas gauge battery", celsius: 37.1),
            (name: "NAND CH0 temp", celsius: 45.0)
        ])

        XCTAssertEqual(readings.socMaxCelsius, 66.4)
        XCTAssertEqual(try XCTUnwrap(readings.socAverageCelsius), 62.5, accuracy: 0.001)
        XCTAssertEqual(readings.sensorCount, 2)
        XCTAssertNil(TemperatureReadings.summarize([]).socMaxCelsius)
    }

    func testLiveSamplerProducesMemoryAndCPU() throws {
        let sampler = SystemStatsSampler()

        let first = sampler.sample()
        var latest = first
        for _ in 0..<Self.maximumCPUSamplingAttempts where latest.cpu == nil {
            Thread.sleep(forTimeInterval: Self.cpuSamplingInterval)
            latest = sampler.sample()
        }

        XCTAssertNotNil(first.memory)
        XCTAssertGreaterThan(first.memory?.totalBytes ?? 0, 0)
        let usage = try XCTUnwrap(latest.cpu, "CPU tick counters never advanced")
        XCTAssertTrue((0.0...100.0).contains(usage.totalPercent))
    }

    func testLiveSamplerReportsDieTemperatureWhenSensorsExist() throws {
        let stats = SystemStatsSampler().sample()
        try XCTSkipIf((stats.temperature?.sensorCount ?? 0) == 0, "No HID die temperature sensors on this machine")

        let hottest = try XCTUnwrap(stats.temperature?.socMaxCelsius)

        XCTAssertTrue(TemperatureReadings.plausibleRange.contains(hottest))
    }
}
