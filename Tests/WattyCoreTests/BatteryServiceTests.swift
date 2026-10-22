import XCTest
@testable import WattyCore

final class BatteryServiceTests: XCTestCase {
    private enum Command {
        static let settings = "/usr/bin/pmset -g"
        static let capabilities = "/usr/bin/pmset -g cap"
        static let batteryStatus = "/usr/bin/pmset -g batt"
        static let details = "/usr/sbin/system_profiler SPPowerDataType -detailLevel mini"
        static let registry = "/usr/sbin/ioreg -l -n AppleSmartBattery -r"
        static let privilegedScriptPrefix = "/usr/bin/osascript -e"
    }

    private enum Output {
        static let automatic = "System-wide power settings:\nCurrently in use:\n standby 1\n powermode 0\n womp 0\n"
        static let highPower = "System-wide power settings:\nCurrently in use:\n standby 1\n powermode 2\n womp 0\n"
        static let capabilities = "Capabilities for AC Power:\n lowpowermode\n highpowermode\n"
        static let batteryStatus = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t55%; discharging; 3:10 remaining present: true\n"
        static let details = """
        Power:
            Battery Information:
              Health Information:
                  Cycle Count: 150
                  Condition: Normal
                  Maximum Capacity: 91%
            AC Charger Information:
              Wattage (W): 96
        """
        static let registry = #"""
        "Voltage" = 12000
        "InstantAmperage" = 18446744073709550616
        "ExternalConnected" = No
        "IsCharging" = No
        "FullyCharged" = No
        "CycleCount" = 121
        "AppleRawMaxCapacity" = 5969
        "DesignCapacity" = 6249
        "Temperature" = 3077
        "CurrentCapacity" = 84
        "MaxCapacity" = 100
        "AvgTimeToEmpty" = 190
        """#
    }

    private final class ScriptedRunner: CommandRunning {
        private let lock = NSLock()
        private var responses: [String: ProcessRunner.Result] = [:]
        private var prefixResponses: [(prefix: String, result: ProcessRunner.Result)] = []
        private var hooks: [(prefix: String, action: () -> Void)] = []
        private var recorded: [String] = []

        var invocations: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func succeed(_ command: String, stdout: String) {
            lock.lock()
            defer { lock.unlock() }
            responses[command] = Self.result(stdout: stdout, status: 0)
        }

        func succeed(prefix: String) {
            lock.lock()
            defer { lock.unlock() }
            prefixResponses.append((prefix, Self.result(stdout: "", status: 0)))
        }

        func fail(_ command: String) {
            lock.lock()
            defer { lock.unlock() }
            responses[command] = Self.result(stdout: "", status: 1)
        }

        func onRun(prefix: String, _ action: @escaping () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            hooks.append((prefix, action))
        }

        func count(of command: String) -> Int {
            invocations.filter { $0 == command }.count
        }

        func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> ProcessRunner.Result {
            let command = ([executable] + arguments).joined(separator: " ")
            lock.lock()
            recorded.append(command)
            let response = responses[command]
                ?? prefixResponses.first { command.hasPrefix($0.prefix) }?.result
                ?? Self.result(stdout: "", status: 127)
            let triggered = hooks.filter { command.hasPrefix($0.prefix) }
            lock.unlock()
            triggered.forEach { $0.action() }
            return response
        }

        private static func result(stdout: String, status: Int32) -> ProcessRunner.Result {
            ProcessRunner.Result(stdout: stdout, stderr: status == 0 ? "" : "scripted failure", terminationStatus: status, didTimeOut: false, duration: 0)
        }
    }

    private final class Rig {
        let runner = ScriptedRunner()
        var powerSource: PowerSourceReadResult = .internalBattery(BatteryServiceTests.internalBattery())
        var smartBattery: SmartBatteryReadResult = .properties(BatteryServiceTests.smartBatteryProperties())
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        init() {
            runner.succeed(Command.settings, stdout: Output.automatic)
            runner.succeed(Command.capabilities, stdout: Output.capabilities)
            runner.succeed(Command.details, stdout: Output.details)
            runner.succeed(Command.batteryStatus, stdout: Output.batteryStatus)
            runner.succeed(Command.registry, stdout: Output.registry)
        }

        func makeService(detailsLifetime: TimeInterval = 300) -> BatteryService {
            BatteryService(
                detailsLifetime: detailsLifetime,
                dependencies: BatteryServiceDependencies(
                    runner: runner,
                    readPowerSource: { self.powerSource },
                    readSmartBattery: { self.smartBattery },
                    now: { self.now }
                )
            )
        }

        func becomeDesktop() {
            powerSource = .noInternalBattery
            smartBattery = .noService
        }
    }

    private static func internalBattery() -> PowerSourceInfo {
        PowerSourceInfo(
            level: 80,
            isCharging: false,
            isCharged: false,
            isFinishingCharge: false,
            externalPower: false,
            timeToFullMinutes: nil,
            timeToEmptyMinutes: 190,
            lowPowerModeActive: false
        )
    }

    private static func smartBatteryProperties() -> [String: Any] {
        [
            "Voltage": 12_000,
            "InstantAmperage": -1_000,
            "ExternalConnected": false,
            "IsCharging": false,
            "FullyCharged": false,
            "CycleCount": 121,
            "CurrentCapacity": 80,
            "MaxCapacity": 100,
            "Temperature": 3_077,
            "AvgTimeToEmpty": 190,
            "AdapterDetails": ["Watts": 100, "Description": "pd charger"] as [String: Any]
        ]
    }

    private static func registry(
        external: Bool,
        milliVolts: Int = 12_000,
        milliAmps: Int?,
        telemetry: [String: Any]? = nil
    ) -> [String: Any] {
        var properties = smartBatteryProperties()
        properties["ExternalConnected"] = external
        properties["IsCharging"] = external && (milliAmps ?? 0) > 0
        properties["Voltage"] = milliVolts
        properties["InstantAmperage"] = milliAmps
        if let telemetry {
            properties["PowerTelemetryData"] = telemetry
        }
        return properties
    }

    private static func onAdapter(charging: Bool) -> PowerSourceInfo {
        PowerSourceInfo(
            level: 80,
            isCharging: charging,
            isCharged: false,
            isFinishingCharge: false,
            externalPower: true,
            timeToFullMinutes: charging ? 48 : nil,
            timeToEmptyMinutes: nil,
            lowPowerModeActive: false
        )
    }

    func testEssentialsSnapshotSpawnsNothingOnceConfigurationIsCached() async throws {
        let rig = Rig()
        let service = rig.makeService()
        _ = await service.fetchSnapshot(depth: .full)
        let spawnedByWarmUp = rig.runner.invocations.count

        var snapshot = BatterySnapshot.empty
        for _ in 0..<5 {
            snapshot = await service.fetchSnapshot(depth: .essentials)
        }

        XCTAssertEqual(rig.runner.invocations.count, spawnedByWarmUp)
        XCTAssertEqual(snapshot.level, 80)
        XCTAssertEqual(snapshot.powerSource, .battery)
        XCTAssertEqual(snapshot.voltageVolts, 12.0)
        XCTAssertEqual(try XCTUnwrap(snapshot.temperatureCelsius), 30.77, accuracy: 0.001)
        XCTAssertEqual(snapshot.cycleCount, 150)
        XCTAssertEqual(snapshot.condition, "Normal")
        XCTAssertEqual(snapshot.powerMode, .automatic)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 190)
        XCTAssertTrue(snapshot.warnings.isEmpty)
    }

    func testEssentialsIgnoresForceDetails() async {
        let rig = Rig()
        let service = rig.makeService()
        _ = await service.fetchSnapshot(depth: .full)
        let spawnedByWarmUp = rig.runner.invocations.count

        _ = await service.fetchSnapshot(depth: .essentials, forceDetails: true)

        XCTAssertEqual(rig.runner.invocations.count, spawnedByWarmUp)
    }

    func testColdEssentialsSnapshotOnlyBootstrapsThePmsetCaches() async {
        let rig = Rig()
        let service = rig.makeService()

        let snapshot = await service.fetchSnapshot(depth: .essentials)

        XCTAssertEqual(Set(rig.runner.invocations), [Command.settings, Command.capabilities])
        XCTAssertEqual(snapshot.cycleCount, 121)
        XCTAssertNil(snapshot.condition)
        XCTAssertEqual(snapshot.powerMode, .automatic)
        XCTAssertEqual(snapshot.powerModeSupport.availableModes, [.automatic, .lowPower, .highPower])

        _ = await service.fetchSnapshot(depth: .essentials)
        XCTAssertEqual(rig.runner.count(of: Command.settings), 1)
        XCTAssertEqual(rig.runner.count(of: Command.capabilities), 1)
    }

    func testFullSnapshotRereadsPmsetEveryTimeButProfilesOnlyWhenExpiredOrForced() async {
        let rig = Rig()
        let service = rig.makeService(detailsLifetime: 300)

        _ = await service.fetchSnapshot(depth: .full)
        _ = await service.fetchSnapshot(depth: .full)

        XCTAssertEqual(rig.runner.count(of: Command.settings), 2)
        XCTAssertEqual(rig.runner.count(of: Command.capabilities), 1)
        XCTAssertEqual(rig.runner.count(of: Command.details), 1)

        rig.now = rig.now.addingTimeInterval(299)
        _ = await service.fetchSnapshot(depth: .full)
        XCTAssertEqual(rig.runner.count(of: Command.details), 1)

        rig.now = rig.now.addingTimeInterval(2)
        _ = await service.fetchSnapshot(depth: .full)
        XCTAssertEqual(rig.runner.count(of: Command.details), 2)

        _ = await service.fetchSnapshot(depth: .full, forceDetails: true)
        XCTAssertEqual(rig.runner.count(of: Command.details), 3)
        XCTAssertEqual(rig.runner.count(of: Command.settings), 5)
    }

    func testDefaultDepthIsFull() async {
        let rig = Rig()
        let service = rig.makeService()

        _ = await service.fetchSnapshot()

        XCTAssertEqual(rig.runner.count(of: Command.details), 1)
    }

    func testFullSnapshotKeepsStaleDetailsWhenProfilerFails() async {
        let rig = Rig()
        let service = rig.makeService(detailsLifetime: 10)
        _ = await service.fetchSnapshot(depth: .full)

        rig.runner.fail(Command.details)
        rig.now = rig.now.addingTimeInterval(60)
        let snapshot = await service.fetchSnapshot(depth: .full)

        XCTAssertEqual(snapshot.cycleCount, 150)
        XCTAssertEqual(snapshot.warnings, ["system_profiler detail read failed"])
    }

    func testMacsWithoutBatteryReportNoBatteryAndSpawnNoBatteryTools() async {
        for depth in [SnapshotDepth.full, .essentials] {
            let rig = Rig()
            rig.becomeDesktop()
            rig.runner.succeed(Command.settings, stdout: Output.highPower)
            let service = rig.makeService()

            let snapshot = await service.fetchSnapshot(depth: depth)

            XCTAssertFalse(snapshot.hasBattery)
            XCTAssertEqual(snapshot.powerSource, .adapter)
            XCTAssertTrue(snapshot.warnings.isEmpty, "\(depth) warnings: \(snapshot.warnings)")
            XCTAssertFalse(snapshot.isCharging)
            XCTAssertFalse(snapshot.isEmpty)
            XCTAssertEqual(snapshot.powerMode, .highPower)
            XCTAssertEqual(snapshot.powerModeSupport.availableModes, [.automatic, .lowPower, .highPower])
            XCTAssertEqual(rig.runner.count(of: Command.registry), 0)
            XCTAssertEqual(rig.runner.count(of: Command.batteryStatus), 0)
            XCTAssertEqual(rig.runner.count(of: Command.details), 0)
        }
    }

    func testDesktopWithUnavailablePowerSourcesDoesNotWarn() async {
        let rig = Rig()
        rig.powerSource = .unavailable
        rig.smartBattery = .noService

        let snapshot = await rig.makeService().fetchSnapshot(depth: .full)

        XCTAssertFalse(snapshot.hasBattery)
        XCTAssertTrue(snapshot.warnings.isEmpty)
        XCTAssertEqual(rig.runner.count(of: Command.registry), 0)
        XCTAssertEqual(rig.runner.count(of: Command.batteryStatus), 0)
    }

    func testEmptySnapshotKeepsHasBatteryTrue() {
        XCTAssertTrue(BatterySnapshot.empty.hasBattery)
    }

    func testRegistryOnlyBatteryCountsAsPresentAndLevelIsClamped() async {
        let rig = Rig()
        rig.powerSource = .noInternalBattery
        rig.smartBattery = .properties(["CurrentCapacity": 5_100, "MaxCapacity": 5_000, "ExternalConnected": true])

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertTrue(snapshot.hasBattery)
        XCTAssertEqual(snapshot.level, 100)
        XCTAssertEqual(snapshot.powerSource, .adapter)
        XCTAssertEqual(rig.runner.count(of: Command.registry), 0)
    }

    func testIoregIsOnlyAFallbackForFailedInProcessReadsOnFullSnapshots() async {
        let rig = Rig()
        rig.smartBattery = .failed("scripted")
        let service = rig.makeService()

        let full = await service.fetchSnapshot(depth: .full)

        XCTAssertEqual(rig.runner.count(of: Command.registry), 1)
        XCTAssertEqual(full.voltageVolts, 12.0)
        XCTAssertEqual(full.amperageAmps, -1.0)
        XCTAssertEqual(full.level, 80)
        XCTAssertTrue(full.warnings.isEmpty)

        let essentials = await service.fetchSnapshot(depth: .essentials)

        XCTAssertEqual(rig.runner.count(of: Command.registry), 1)
        XCTAssertNil(essentials.voltageVolts)
        XCTAssertEqual(essentials.level, 80)
        XCTAssertEqual(essentials.warnings, ["AppleSmartBattery read failed"])
    }

    func testHealthyInProcessReadNeverSpawnsIoreg() async {
        let rig = Rig()
        let service = rig.makeService()

        _ = await service.fetchSnapshot(depth: .full)
        _ = await service.fetchSnapshot(depth: .essentials)

        XCTAssertEqual(rig.runner.count(of: Command.registry), 0)
        XCTAssertEqual(rig.runner.count(of: Command.batteryStatus), 0)
    }

    func testFailedIoregFallbackIsReported() async {
        let rig = Rig()
        rig.smartBattery = .failed("scripted")
        rig.runner.fail(Command.registry)

        let snapshot = await rig.makeService().fetchSnapshot(depth: .full)

        XCTAssertEqual(snapshot.warnings, ["ioreg battery read failed"])
        XCTAssertEqual(snapshot.level, 80)
        XCTAssertNil(snapshot.voltageVolts)
    }

    func testPmsetBatteryIsLastResortWhenEveryBatterySourceFails() async {
        let rig = Rig()
        rig.powerSource = .unavailable
        rig.smartBattery = .failed("scripted")
        rig.runner.fail(Command.registry)

        let snapshot = await rig.makeService().fetchSnapshot(depth: .full)

        XCTAssertEqual(rig.runner.count(of: Command.batteryStatus), 1)
        XCTAssertEqual(snapshot.level, 55)
        XCTAssertEqual(snapshot.powerSource, .battery)
        XCTAssertEqual(snapshot.timeToEmptyMinutes, 190)
        XCTAssertEqual(snapshot.warnings, ["IOKit power source read failed", "ioreg battery read failed"])
    }

    func testUnavailablePowerSourcesWithHealthyRegistryWarnWithoutSpawningPmsetBattery() async {
        let rig = Rig()
        rig.powerSource = .unavailable

        let snapshot = await rig.makeService().fetchSnapshot(depth: .full)

        XCTAssertEqual(snapshot.warnings, ["IOKit power source read failed"])
        XCTAssertEqual(snapshot.level, 80)
        XCTAssertEqual(rig.runner.count(of: Command.batteryStatus), 0)
        XCTAssertEqual(rig.runner.count(of: Command.registry), 0)
    }

    func testSetPowerModeInvalidatesCachedSettings() async {
        let rig = Rig()
        let service = rig.makeService()
        let initial = await service.fetchSnapshot(depth: .full)
        XCTAssertEqual(initial.powerMode, .automatic)
        rig.runner.succeed(prefix: Command.privilegedScriptPrefix)
        rig.runner.onRun(prefix: Command.privilegedScriptPrefix) {
            rig.runner.succeed(Command.settings, stdout: Output.highPower)
        }
        let settingsReadsBeforeChange = rig.runner.count(of: Command.settings)

        let result = await service.setPowerMode(.highPower)

        XCTAssertTrue(result.success, result.message)
        XCTAssertEqual(result.resultingMode, .highPower)
        let settingsReadsAfterChange = rig.runner.count(of: Command.settings)
        XCTAssertEqual(settingsReadsAfterChange - settingsReadsBeforeChange, 2)

        let afterwards = await service.fetchSnapshot(depth: .essentials)

        XCTAssertEqual(rig.runner.count(of: Command.settings), settingsReadsAfterChange + 1)
        XCTAssertEqual(afterwards.powerMode, .highPower)

        _ = await service.fetchSnapshot(depth: .essentials)
        XCTAssertEqual(rig.runner.count(of: Command.settings), settingsReadsAfterChange + 1)
    }

    func testSetPowerModeReportsWhenTheSystemKeepsAnotherMode() async {
        let rig = Rig()
        let service = rig.makeService()
        rig.runner.succeed(prefix: Command.privilegedScriptPrefix)

        let result = await service.setPowerMode(.lowPower)

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.message, "System kept Automatic")
        XCTAssertEqual(result.resultingMode, .automatic)
    }

    func testSetPowerModeFailureIsPropagatedWithoutPrompting() async {
        let rig = Rig()
        let service = rig.makeService()

        let result = await service.setPowerMode(.lowPower)

        XCTAssertFalse(result.success)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertEqual(rig.runner.invocations.filter { $0.hasPrefix(Command.privilegedScriptPrefix) }.count, 1)
    }

    func testPositiveBatteryReadingsWhileOnBatteryAreReportedAsADischarge() async throws {
        let rig = Rig()
        rig.smartBattery = .properties(Self.registry(external: false, milliAmps: 1_800))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(snapshot.powerSource, .battery)
        XCTAssertEqual(try XCTUnwrap(snapshot.batteryPowerWatts), -21.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.amperageAmps), -1.8, accuracy: 0.0001)
    }

    func testPositiveTelemetryBatteryPowerWhileOnBatteryIsAlsoADischarge() async throws {
        let rig = Rig()
        let telemetry: [String: Any] = ["BatteryPower": 21_900]
        var properties = Self.registry(external: false, milliAmps: nil, telemetry: telemetry)
        properties.removeValue(forKey: "Voltage")
        properties.removeValue(forKey: "InstantAmperage")
        rig.smartBattery = .properties(properties)

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(try XCTUnwrap(snapshot.batteryPowerWatts), -21.9, accuracy: 0.0001)
    }

    func testNegativeSystemLoadIsReportedAsUnavailable() async {
        let rig = Rig()
        let telemetry: [String: Any] = ["SystemLoad": -21_900]
        rig.smartBattery = .properties(Self.registry(external: false, milliAmps: -1_800, telemetry: telemetry))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertNil(snapshot.systemLoadWatts)
    }

    func testChargingOnTheAdapterKeepsThePositiveBatteryPowerAndTheLoad() async throws {
        let rig = Rig()
        rig.powerSource = .internalBattery(Self.onAdapter(charging: true))
        let telemetry: [String: Any] = ["SystemPowerIn": 42_500, "SystemLoad": 21_300]
        rig.smartBattery = .properties(Self.registry(external: true, milliVolts: 12_610, milliAmps: 1_570, telemetry: telemetry))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(snapshot.powerSource, .adapter)
        XCTAssertEqual(try XCTUnwrap(snapshot.batteryPowerWatts), 19.7977, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.amperageAmps), 1.57, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.systemLoadWatts), 21.3, accuracy: 0.0001)
    }

    func testDischargingWhilePluggedInKeepsTheNegativeBatteryPower() async throws {
        let rig = Rig()
        rig.powerSource = .internalBattery(Self.onAdapter(charging: false))
        rig.smartBattery = .properties(Self.registry(external: true, milliAmps: -2_000))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(snapshot.powerSource, .adapter)
        XCTAssertEqual(try XCTUnwrap(snapshot.batteryPowerWatts), -24.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(snapshot.amperageAmps), -2.0, accuracy: 0.0001)
    }

    func testTheSnapshotCarriesThePowerAccumulationOfTheRegistry() async {
        let rig = Rig()
        rig.powerSource = .internalBattery(Self.onAdapter(charging: true))
        let telemetry: [String: Any] = [
            "AccumulatedBatteryPower": 2_653_160_571,
            "BatteryPowerAccumulatorCount": 126_349,
            "AccumulatedBatteryDischarge": UInt64(18_446_744_071_188_733_378),
            "BatteryDischargeAccumulatorCount": 166_218
        ]
        rig.smartBattery = .properties(Self.registry(external: true, milliAmps: 1_000, telemetry: telemetry))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(snapshot.powerAccumulation, PowerAccumulation(milliwattTicks: 132_342_333, ticks: 292_567))
    }

    func testWithoutAccumulatorsTheSnapshotHasNoAccumulation() async {
        let rig = Rig()

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertNil(snapshot.powerAccumulation)
    }

    func testTheServiceNeverDecidesTheNetFlowItself() async {
        let rig = Rig()
        rig.powerSource = .internalBattery(Self.onAdapter(charging: true))
        rig.smartBattery = .properties(Self.registry(external: true, milliAmps: -2_000))

        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)

        XCTAssertEqual(snapshot.netFlow, .unknown)
        XCTAssertEqual(snapshot.chargeState, .charging)
    }

    func testTheStatusReportReadsTheSanitizedSnapshotRightAfterUnplugging() async {
        let rig = Rig()
        let telemetry: [String: Any] = ["SystemLoad": -21_600]
        rig.smartBattery = .properties(Self.registry(external: false, milliAmps: 1_800, telemetry: telemetry))
        let snapshot = await rig.makeService().fetchSnapshot(depth: .essentials)
        let stats = SystemStats(date: rig.now, cpu: nil, memory: nil, temperature: nil)

        let report = StatusReport(snapshot: snapshot, stats: stats, generatedAt: rig.now)

        XCTAssertEqual(report.battery.powerWatts, -21.6)
        XCTAssertEqual(report.battery.amperageAmps, -1.8)
        XCTAssertEqual(report.power.systemLoadWatts, 21.6)
    }
}
