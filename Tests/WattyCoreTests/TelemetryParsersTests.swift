import XCTest
@testable import WattyCore

final class TelemetryParsersTests: XCTestCase {
    func testParsesPmsetChargingOutput() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=7602275)\t96%; charging; 0:20 remaining present: true
        """

        let info = TelemetryParsers.parsePmsetBattery(output)

        XCTAssertEqual(info.level, 96)
        XCTAssertTrue(info.isCharging)
        XCTAssertEqual(info.timeRemainingText, "0:20")
        XCTAssertEqual(info.timeRemainingMinutes, 20)
        XCTAssertEqual(info.powerSource, .adapter)
    }

    func testParsesUnifiedPowerModeFromPmsetSettings() {
        let output = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         standby              1
         Sleep On Power Button 1
         hibernatefile        /var/vm/sleepimage
         sleep                0 (sleep prevented by caffeinate, powerd)
         powermode            2
         womp                 0
        """

        let info = TelemetryParsers.parsePmsetSettings(output)

        XCTAssertEqual(info.powerMode, 2)
        XCTAssertNil(info.lowPowerMode)
        XCTAssertTrue(info.unifiedKeyAvailable)
        XCTAssertEqual(info.resolvedMode, .highPower)
    }

    func testParsesLegacyPowerModeKeysFromPmsetSettings() {
        let output = """
        Currently in use:
         lowpowermode         1
         highpowermode        0
        """

        let info = TelemetryParsers.parsePmsetSettings(output)

        XCTAssertNil(info.powerMode)
        XCTAssertFalse(info.unifiedKeyAvailable)
        XCTAssertEqual(info.resolvedMode, .lowPower)
        XCTAssertNil(TelemetryParsers.parsePmsetSettings("Currently in use:\n sleep 0\n").resolvedMode)
        XCTAssertEqual(TelemetryParsers.parsePmsetSettings(" lowpowermode 0\n highpowermode 0\n").resolvedMode, .automatic)
    }

    func testParsesPmsetCapabilities() {
        let output = """
        Capabilities for AC Power:
         displaysleep
         disksleep
         lowpowermode
         highpowermode
        """

        let capabilities = TelemetryParsers.parsePmsetCapabilities(output)

        XCTAssertTrue(capabilities.contains("lowpowermode"))
        XCTAssertTrue(capabilities.contains("highpowermode"))
        XCTAssertFalse(capabilities.contains("capabilities for ac power:"))
    }

    func testPowerModeSupportHidesHighPowerWhenUnsupported() {
        let support = PowerModeSupport(
            capabilities: ["lowpowermode"],
            settings: PmsetSettingsInfo(lowPowerMode: 0)
        )

        XCTAssertFalse(support.unifiedKeyAvailable)
        XCTAssertEqual(support.availableModes, [.automatic, .lowPower])
        XCTAssertEqual(
            PowerMode.highPower.shellScript(support: PowerModeSupport(unifiedKeyAvailable: true, supportsLowPower: true, supportsHighPower: true)),
            "/usr/bin/pmset -a powermode 2 || (/usr/bin/pmset -a lowpowermode 0 && /usr/bin/pmset -a highpowermode 1)"
        )
        XCTAssertEqual(
            PowerMode.automatic.shellScript(support: support),
            "/usr/bin/pmset -a lowpowermode 0"
        )
    }

    func testParsesIoregTelemetryAndUnsignedNegativeCurrent() {
        let output = #"""
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
        "AvgTimeToEmpty" = 65535
        "AvgTimeToFull" = 48
        "PowerTelemetryData" = {"SystemPowerIn"=21000,"SystemLoad"=19000,"BatteryPower"=18446744073709546616}
        "AdapterDetails" = {"Watts"=100,"Description"="pd charger"}
        """#

        let info = TelemetryParsers.parseIoregBattery(output)

        XCTAssertEqual(info.voltageVolts, 12.0)
        XCTAssertEqual(info.amperageAmps, -1.0)
        XCTAssertEqual(info.systemPowerWatts, 21.0)
        XCTAssertEqual(info.systemLoadWatts, 19.0)
        XCTAssertEqual(info.batteryPowerWatts, -12.0)
        XCTAssertEqual(info.adapterRatedWatts, 100)
        XCTAssertEqual(info.adapterDescription, "pd charger")
        XCTAssertEqual(info.cycleCount, 121)
        XCTAssertEqual(info.maximumCapacityPercent, 96)
        XCTAssertEqual(info.currentCapacityPercent, 84)
        XCTAssertNil(info.timeToEmptyMinutes)
        XCTAssertEqual(info.timeToFullMinutes, 48)
        XCTAssertEqual(try XCTUnwrap(info.temperatureCelsius), 30.77, accuracy: 0.001)
    }

    func testBatteryPowerDoesNotUseAccumulatedBatteryPower() throws {
        let output = #"""
        "Voltage" = 13256
        "InstantAmperage" = 332
        "PowerTelemetryData" = {"AccumulatedBatteryPower"=66001807,"BatteryPower"=4413}
        """#

        let info = TelemetryParsers.parseIoregBattery(output)

        XCTAssertEqual(try XCTUnwrap(info.batteryPowerWatts), 4.400992, accuracy: 0.001)
    }

    func testParsesSystemProfilerPowerDetails() {
        let output = """
        Power:
            Battery Information:
              Health Information:
                  Cycle Count: 121
                  Condition: Normal
                  Maximum Capacity: 99%
            System Power Settings:
              AC Power:
                  High Power Mode: No
                  Low Power Mode: Yes
            AC Charger Information:
              Wattage (W): 100
        """

        let info = TelemetryParsers.parseSystemProfilerPower(output)

        XCTAssertEqual(info.cycleCount, 121)
        XCTAssertEqual(info.condition, "Normal")
        XCTAssertEqual(info.maximumCapacityPercent, 99)
        XCTAssertEqual(info.adapterRatedWatts, 100)
        XCTAssertEqual(info.lowPowerMode, true)
        XCTAssertEqual(info.highPowerMode, false)
    }

    func testAggregatesEnergyByResolvedIdentity() {
        let rows = [
            ProcessEnergyRow(pid: 10, command: "Google Chrome Helper", cpuPercent: 5, memoryBytes: 100),
            ProcessEnergyRow(pid: 11, command: "Google Chrome", cpuPercent: 2, memoryBytes: 200),
            ProcessEnergyRow(pid: 12, command: "Watty", cpuPercent: 9, memoryBytes: 300),
            ProcessEnergyRow(pid: 13, command: "Slack", cpuPercent: 40, memoryBytes: 400)
        ]

        let apps = TelemetryParsers.aggregateEnergy(rows) { row in
            switch row.pid {
            case 12: return EnergyIdentity(key: "com.jmtes.watty", name: "Watty")
            case 13: return EnergyIdentity(key: "com.tinyspeck.slackmacgap", name: "Slack")
            default: return EnergyIdentity(key: "com.google.Chrome", name: "Google Chrome")
            }
        }

        XCTAssertEqual(apps.map(\.name), ["Slack", "Google Chrome"])
        XCTAssertEqual(apps[1].pids, [10, 11])
        XCTAssertEqual(apps[1].memoryBytes, 300)
        XCTAssertEqual(apps[1].cpuPercent, 7)
    }

    func testEnergyRowsFromReadingDeltasConvertMachTicks() {
        let before: [pid_t: ProcessEnergySampler.Reading] = [
            1: .init(cpuTicks: 24_000_000, footprintBytes: 10),
            2: .init(cpuTicks: 0, footprintBytes: 20),
            3: .init(cpuTicks: 5, footprintBytes: 30)
        ]
        let after: [pid_t: ProcessEnergySampler.Reading] = [
            1: .init(cpuTicks: 36_000_000, footprintBytes: 11),
            2: .init(cpuTicks: 24_000, footprintBytes: 20),
            4: .init(cpuTicks: 9, footprintBytes: 40)
        ]

        let rows = ProcessEnergySampler.rows(from: before, to: after, elapsed: 2, nanosecondsPerTick: 125.0 / 3.0)

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].pid, 1)
        XCTAssertEqual(rows[0].cpuPercent, 25, accuracy: 0.001)
        XCTAssertEqual(rows[0].memoryBytes, 11)
        XCTAssertGreaterThan(ProcessEnergySampler.nanosecondsPerTick, 0)
    }

    func testLiveSamplerMeasuresBusyProcess() throws {
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try busy.run()
        defer { busy.terminate() }
        let sampler = ProcessEnergySampler()

        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.5)
        let rows = try XCTUnwrap(sampler.sample())
        let row = try XCTUnwrap(rows.first { $0.pid == Int(busy.processIdentifier) })

        XCTAssertGreaterThan(row.cpuPercent, 25)
    }

    func testParsesPsCpuTimeAndComputesDeltas() throws {
        XCTAssertEqual(SystemProcessSampler.centiseconds(from: "6988:02.40"), 6988 * 6_000 + 240)
        XCTAssertEqual(SystemProcessSampler.centiseconds(from: "0:01.50"), 150)
        XCTAssertEqual(SystemProcessSampler.centiseconds(from: "1:02:03.25"), 3_723 * 100 + 25)
        XCTAssertEqual(SystemProcessSampler.centiseconds(from: "2-01:02:03.00"), (2 * 86_400 + 3_723) * 100)
        XCTAssertNil(SystemProcessSampler.centiseconds(from: "abc"))

        let first = """
          175    88 6988:02.40 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
          407     0 616:25.60 /usr/libexec/searchpartyd
         4668   501 10:00.00 /Applications/Example.app/Contents/MacOS/Example
        """
        let second = """
          175    88 6988:03.40 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
          407     0 616:25.60 /usr/libexec/searchpartyd
         4668   501 10:02.00 /Applications/Example.app/Contents/MacOS/Example
        """
        let sampler = SystemProcessSampler(excludedUID: 501)

        XCTAssertNil(sampler.rows(from: first, uptime: 100))
        let rows = try XCTUnwrap(sampler.rows(from: second, uptime: 102))

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].pid, 175)
        XCTAssertEqual(rows[0].command, "WindowServer")
        XCTAssertEqual(rows[0].executablePath, "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer")
        XCTAssertEqual(rows[0].cpuPercent, 50, accuracy: 0.001)
        XCTAssertEqual(rows[0].memoryBytes, 0)
    }

    func testLiveEnergySamplerWarmsUpThenReportsRows() {
        let sampler = ProcessEnergySampler()

        XCTAssertNil(sampler.sample())
        XCTAssertTrue(sampler.isWarmedUp)
        Thread.sleep(forTimeInterval: 0.3)
        let rows = sampler.sample()

        XCTAssertNotNil(rows)
    }

    func testChargeStateAndTimeText() {
        var snapshot = BatterySnapshot.empty
        XCTAssertEqual(snapshot.chargeState, .unknown)

        snapshot.lastUpdated = Date()
        snapshot.powerSource = .adapter
        snapshot.isCharging = true
        snapshot.timeToFullMinutes = 75
        XCTAssertEqual(snapshot.chargeState, .charging)
        XCTAssertEqual(snapshot.timeRemainingText, "1:15 to full")

        snapshot.timeToFullMinutes = nil
        XCTAssertEqual(snapshot.timeRemainingText, "Calculating time to full")
        snapshot.isFinishingCharge = true
        XCTAssertEqual(snapshot.timeRemainingText, "Finishing charge")
        snapshot.isFinishingCharge = false
        snapshot.level = 100
        XCTAssertEqual(snapshot.timeRemainingText, "Finishing charge")

        snapshot.isCharging = false
        snapshot.level = 80
        XCTAssertEqual(snapshot.chargeState, .pluggedInNotCharging)

        snapshot.isFullyCharged = true
        XCTAssertEqual(snapshot.chargeState, .charged)

        snapshot.powerSource = .battery
        snapshot.isFullyCharged = false
        snapshot.timeToEmptyMinutes = nil
        XCTAssertEqual(snapshot.chargeState, .onBattery)
        XCTAssertEqual(snapshot.timeRemainingText, "Calculating time left")
    }
}
