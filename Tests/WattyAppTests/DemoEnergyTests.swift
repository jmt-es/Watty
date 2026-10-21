import XCTest
@testable import Watty
import WattyCore

final class DemoEnergyTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private static let allowedNames: Set<String> = [
        "Safari", "Music", "Photos", "Mail", "Messages", "Finder", "WindowServer"
    ]

    private func sample(_ scenario: DemoScenario = .charging) -> EnergySample {
        DemoEnergy.sample(for: scenario, at: date)
    }

    func testOnlyAppsEveryMacHasAndOneSystemProcessAreListed() {
        for scenario in DemoScenario.allCases {
            let names = Set(sample(scenario).consumers.map(\.name))

            XCTAssertTrue(names.isSubset(of: Self.allowedNames), "\(scenario): \(names)")
            XCTAssertTrue(names.contains("WindowServer"), "\(scenario)")
            XCTAssertEqual(sample(scenario).consumers.count, DemoEnergy.applications.count + 1)
        }
    }

    func testTheSampleIsReadyAndSortedByCPU() {
        let sample = sample()

        XCTAssertFalse(sample.isEmpty)
        XCTAssertFalse(sample.isWarmingUp)
        XCTAssertFalse(sample.failed)
        XCTAssertEqual(sample.sampledAt, date)
        XCTAssertEqual(sample.consumers.map(\.cpuPercent), sample.consumers.map(\.cpuPercent).sorted(by: >))
    }

    func testNoConsumerPointsAtARealProcess() {
        XCTAssertTrue(sample().consumers.allSatisfy { $0.pid == nil })
    }

    func testAppsHaveAMemoryFootprintAndTheSystemProcessDoesNot() throws {
        let consumers = sample().consumers
        let system = try XCTUnwrap(consumers.first { $0.name == DemoEnergy.systemProcessName })

        XCTAssertEqual(system.memoryBytes, 0)
        XCTAssertNotNil(system.icon)
        for consumer in consumers where consumer.name != DemoEnergy.systemProcessName {
            XCTAssertGreaterThan(consumer.memoryBytes, 0, consumer.name)
        }
    }

    func testIconsComeFromTheBundlesThatExistOnThisMac() {
        for application in DemoEnergy.applications {
            let consumer = sample().consumers.first { $0.id == application.identifier }
            let bundleExists = DemoEnergy.existingBundlePath(in: application.bundlePaths) != nil

            XCTAssertEqual(consumer?.icon != nil, bundleExists, application.name)
        }
    }

    func testIdentifiersAreUnique() {
        let identifiers = sample().consumers.map(\.id)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testLighterScenariosUseLessCPU() throws {
        let charging = try XCTUnwrap(sample(.charging).consumers.first)
        let battery = try XCTUnwrap(sample(.battery).consumers.first)
        let desktop = try XCTUnwrap(sample(.desktop).consumers.first)

        XCTAssertGreaterThan(charging.cpuPercent, battery.cpuPercent)
        XCTAssertGreaterThan(battery.cpuPercent, desktop.cpuPercent)
    }

    func testSampleIsDeterministic() {
        XCTAssertEqual(sample(), sample())
    }
}
