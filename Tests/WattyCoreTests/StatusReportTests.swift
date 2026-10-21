import XCTest
@testable import WattyCore

final class StatusReportTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_792_598_644)

    private func snapshot(_ configure: (inout BatterySnapshot) -> Void = { _ in }) -> BatterySnapshot {
        var snapshot = BatterySnapshot.empty
        snapshot.hasBattery = true
        snapshot.level = 72
        snapshot.isCharging = true
        snapshot.powerSource = .adapter
        snapshot.timeToFullMinutes = 98
        snapshot.voltageVolts = 12.3234
        snapshot.amperageAmps = 2.3814
        snapshot.batteryPowerWatts = 29.34056
        snapshot.systemPowerWatts = 59.8449
        snapshot.systemLoadWatts = 30.468
        snapshot.adapterRatedWatts = 70
        snapshot.cycleCount = 257
        snapshot.condition = "Normal"
        snapshot.maximumCapacityPercent = 89
        snapshot.temperatureCelsius = 30.634
        snapshot.powerMode = .highPower
        snapshot.lowPowerModeActive = false
        snapshot.lastUpdated = generatedAt
        configure(&snapshot)
        return snapshot
    }

    private func stats(
        cpu: CPUUsage? = CPUUsage(userPercent: 8.14, systemPercent: 4.26),
        memory: MemoryUsage? = MemoryUsage(
            usedBytes: 19_000_000_000,
            appBytes: 12_000_000_000,
            wiredBytes: 4_000_000_000,
            compressedBytes: 3_000_000_000,
            totalBytes: 34_359_738_368,
            swapUsedBytes: 0
        ),
        temperature: TemperatureReadings? = TemperatureReadings(socMaxCelsius: 55.46, socAverageCelsius: 50.1, sensorCount: 4)
    ) -> SystemStats {
        SystemStats(date: generatedAt, cpu: cpu, memory: memory, temperature: temperature)
    }

    private func report(
        _ snapshot: BatterySnapshot? = nil,
        stats: SystemStats? = nil
    ) -> StatusReport {
        StatusReport(
            snapshot: snapshot ?? self.snapshot(),
            stats: stats ?? self.stats(),
            generatedAt: generatedAt
        )
    }

    private func jsonObject(_ report: some Encodable) throws -> [String: Any] {
        let text = try ReportEncoder.jsonString(for: report)
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }

    func testMapsChargingSnapshotToReport() {
        let report = report()

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.wattyVersion, WattyVersion.current)
        XCTAssertTrue(report.hasBattery)
        XCTAssertEqual(report.battery.levelPercent, 72)
        XCTAssertEqual(report.battery.state, .charging)
        XCTAssertEqual(report.battery.timeToFullMinutes, 98)
        XCTAssertNil(report.battery.timeToEmptyMinutes)
        XCTAssertEqual(report.battery.cycleCount, 257)
        XCTAssertEqual(report.battery.maximumCapacityPercent, 89)
        XCTAssertEqual(report.battery.condition, "Normal")
        XCTAssertEqual(report.power.source, .adapter)
        XCTAssertEqual(report.power.adapterRatedWatts, 70)
        XCTAssertEqual(report.power.mode, .highPower)
        XCTAssertEqual(report.power.lowPowerModeActive, false)
        XCTAssertEqual(report.system.memoryTotalBytes, 34_359_738_368)
        XCTAssertEqual(report.system.swapUsedBytes, 0)
    }

    func testRoundsMeasurementsToDocumentedPrecision() {
        let report = report()

        XCTAssertEqual(report.battery.powerWatts, 29.34)
        XCTAssertEqual(report.battery.voltageVolts, 12.323)
        XCTAssertEqual(report.battery.amperageAmps, 2.381)
        XCTAssertEqual(report.battery.temperatureCelsius, 30.6)
        XCTAssertEqual(report.power.systemInputWatts, 59.84)
        XCTAssertEqual(report.power.systemLoadWatts, 30.47)
        XCTAssertEqual(report.system.socTemperatureCelsius, 55.5)
        XCTAssertEqual(report.system.cpuPercent, 12.4)
        XCTAssertEqual(report.system.cpuUserPercent, 8.1)
        XCTAssertEqual(report.system.cpuSystemPercent, 4.3)
        XCTAssertEqual(report.system.memoryPercent, 55.3)
    }

    func testOnBatteryReportsTimeToEmptyOnly() {
        let report = report(snapshot {
            $0.isCharging = false
            $0.powerSource = .battery
            $0.timeToFullMinutes = 30
            $0.timeToEmptyMinutes = 215
            $0.adapterRatedWatts = 70
            $0.batteryPowerWatts = -11.2
            $0.systemPowerWatts = 0
        })

        XCTAssertEqual(report.battery.state, .onBattery)
        XCTAssertNil(report.battery.timeToFullMinutes)
        XCTAssertEqual(report.battery.timeToEmptyMinutes, 215)
        XCTAssertEqual(report.battery.powerWatts, -11.2)
        XCTAssertEqual(report.power.source, .battery)
        XCTAssertNil(report.power.adapterRatedWatts)
    }

    func testPluggedInStatesCarryNoTimeEstimate() {
        let charged = report(snapshot {
            $0.isCharging = false
            $0.isFullyCharged = true
            $0.level = 100
            $0.timeToFullMinutes = 5
            $0.timeToEmptyMinutes = 400
        })
        let notCharging = report(snapshot {
            $0.isCharging = false
            $0.timeToFullMinutes = 5
            $0.timeToEmptyMinutes = 400
        })

        XCTAssertEqual(charged.battery.state, .charged)
        XCTAssertEqual(notCharging.battery.state, .pluggedInNotCharging)
        for report in [charged, notCharging] {
            XCTAssertNil(report.battery.timeToFullMinutes)
            XCTAssertNil(report.battery.timeToEmptyMinutes)
        }
    }

    func testNoBatteryNullsBatteryFieldsAndKeepsSystemFields() throws {
        let report = report(snapshot {
            $0.hasBattery = false
            $0.level = 0
            $0.isCharging = false
            $0.powerSource = .adapter
            $0.cycleCount = nil
            $0.powerMode = .automatic
            $0.lowPowerModeActive = false
        })
        let object = try jsonObject(report)
        let battery = try XCTUnwrap(object["battery"] as? [String: Any])

        XCTAssertEqual(object["has_battery"] as? Bool, false)
        XCTAssertEqual(battery.count, 11)
        for (key, value) in battery {
            XCTAssertTrue(value is NSNull, "\(key) should be null without a battery")
        }
        XCTAssertNil(report.power.source)
        XCTAssertEqual(report.power.mode, .automatic)
        XCTAssertEqual(report.power.lowPowerModeActive, false)
        XCTAssertEqual(report.system.cpuPercent, 12.4)
        XCTAssertEqual(report.system.socTemperatureCelsius, 55.5)
        XCTAssertNotNil(report.system.memoryPercent)
    }

    func testEmptySnapshotCarriesNoFakeBatteryReadings() {
        let report = StatusReport(snapshot: .empty, stats: stats(), generatedAt: generatedAt)

        XCTAssertNil(report.battery.levelPercent)
        XCTAssertNil(report.battery.state)
    }

    func testUnknownValuesEncodeAsExplicitNull() throws {
        let report = report(
            snapshot {
                $0.voltageVolts = nil
                $0.amperageAmps = nil
                $0.batteryPowerWatts = nil
                $0.systemPowerWatts = nil
                $0.systemLoadWatts = nil
                $0.adapterRatedWatts = nil
                $0.cycleCount = nil
                $0.condition = nil
                $0.maximumCapacityPercent = nil
                $0.temperatureCelsius = nil
                $0.timeToFullMinutes = nil
                $0.powerMode = nil
                $0.lowPowerModeActive = nil
            },
            stats: stats(cpu: nil, memory: nil, temperature: nil)
        )
        let object = try jsonObject(report)
        let battery = try XCTUnwrap(object["battery"] as? [String: Any])
        let power = try XCTUnwrap(object["power"] as? [String: Any])
        let system = try XCTUnwrap(object["system"] as? [String: Any])

        for key in ["voltage_volts", "amperage_amps", "power_watts", "cycle_count", "condition",
                    "maximum_capacity_percent", "temperature_celsius", "time_to_full_minutes", "time_to_empty_minutes"] {
            XCTAssertTrue(battery[key] is NSNull, "battery.\(key) should be an explicit null")
        }
        for key in ["adapter_rated_watts", "system_input_watts", "system_load_watts", "mode", "low_power_mode_active"] {
            XCTAssertTrue(power[key] is NSNull, "power.\(key) should be an explicit null")
        }
        for (key, value) in system {
            XCTAssertTrue(value is NSNull, "system.\(key) should be an explicit null")
        }
        XCTAssertEqual(battery["level_percent"] as? Int, 72)
    }

    func testDocumentedKeysAreExactlyThePublishedSchema() throws {
        let object = try jsonObject(report())

        XCTAssertEqual(Set(object.keys), [
            "schema_version", "watty_version", "timestamp", "has_battery",
            "battery", "power", "system", "warnings"
        ])
        XCTAssertEqual(Set(try XCTUnwrap(object["battery"] as? [String: Any]).keys), [
            "level_percent", "state", "time_to_full_minutes", "time_to_empty_minutes", "power_watts",
            "voltage_volts", "amperage_amps", "temperature_celsius", "cycle_count",
            "maximum_capacity_percent", "condition"
        ])
        XCTAssertEqual(Set(try XCTUnwrap(object["power"] as? [String: Any]).keys), [
            "source", "adapter_rated_watts", "system_input_watts", "system_load_watts",
            "mode", "low_power_mode_active"
        ])
        XCTAssertEqual(Set(try XCTUnwrap(object["system"] as? [String: Any]).keys), [
            "soc_temperature_celsius", "cpu_percent", "cpu_user_percent", "cpu_system_percent",
            "memory_percent", "memory_used_bytes", "memory_total_bytes", "swap_used_bytes"
        ])
    }

    func testEnvelopeValues() throws {
        let object = try jsonObject(report())

        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["watty_version"] as? String, WattyVersion.current)
        XCTAssertEqual(object["timestamp"] as? String, "2026-10-21T16:04:04Z")
        XCTAssertEqual(object["has_battery"] as? Bool, true)
        XCTAssertEqual((object["warnings"] as? [String])?.count, 0)
    }

    func testEnumeratedValuesUseSnakeCaseIdentifiers() throws {
        let object = try jsonObject(report())
        let battery = try XCTUnwrap(object["battery"] as? [String: Any])
        let power = try XCTUnwrap(object["power"] as? [String: Any])

        XCTAssertEqual(battery["state"] as? String, "charging")
        XCTAssertEqual(power["source"] as? String, "adapter")
        XCTAssertEqual(power["mode"] as? String, "high_power")
        XCTAssertEqual(ReportChargeState.pluggedInNotCharging.rawValue, "plugged_in_not_charging")
        XCTAssertEqual(ReportChargeState.onBattery.rawValue, "on_battery")
        XCTAssertEqual(ReportPowerMode.lowPower.rawValue, "low_power")
    }

    func testJSONIsPrettyPrintedWithSortedKeys() throws {
        let text = try ReportEncoder.jsonString(for: report())
        let topLevelKeys = text
            .split(separator: "\n")
            .filter { $0.hasPrefix("  \"") }
            .compactMap { line in line.split(separator: "\"").dropFirst().first.map(String.init) }

        XCTAssertGreaterThan(text.split(separator: "\n").count, 20)
        XCTAssertEqual(topLevelKeys, topLevelKeys.sorted())
        XCTAssertEqual(topLevelKeys.first, "battery")
        XCTAssertEqual(topLevelKeys.last, "watty_version")
    }

    func testJSONDoesNotEscapeSlashes() throws {
        let report = report(snapshot { $0.warnings = ["/usr/bin/pmset battery read failed"] })

        let text = try ReportEncoder.jsonString(for: report)

        XCTAssertTrue(text.contains("/usr/bin/pmset battery read failed"))
        XCTAssertFalse(text.contains("\\/"))
    }

    func testSystemLoadIsDerivedWhenTheSMCDoesNotReportIt() {
        let charging = report(snapshot {
            $0.systemLoadWatts = nil
            $0.systemPowerWatts = 60
            $0.batteryPowerWatts = 35
        })
        let onBattery = report(snapshot {
            $0.systemLoadWatts = nil
            $0.powerSource = .battery
            $0.isCharging = false
            $0.systemPowerWatts = 0
            $0.batteryPowerWatts = -12.5
        })
        let unknownBatteryFlow = report(snapshot {
            $0.systemLoadWatts = nil
            $0.batteryPowerWatts = nil
        })

        XCTAssertEqual(charging.power.systemLoadWatts, 25)
        XCTAssertEqual(onBattery.power.systemLoadWatts, 12.5)
        XCTAssertNil(unknownBatteryFlow.power.systemLoadWatts)
    }

    func testReportedSystemLoadWinsOverDerivedValue() {
        let report = report(snapshot {
            $0.systemLoadWatts = 18.2
            $0.systemPowerWatts = 60
            $0.batteryPowerWatts = 35
        })

        XCTAssertEqual(report.power.systemLoadWatts, 18.2)
    }

    func testNonFiniteReadingsBecomeNull() {
        let report = report(snapshot {
            $0.voltageVolts = .nan
            $0.batteryPowerWatts = .infinity
            $0.temperatureCelsius = -.infinity
        })

        XCTAssertNil(report.battery.voltageVolts)
        XCTAssertNil(report.battery.powerWatts)
        XCTAssertNil(report.battery.temperatureCelsius)
        XCTAssertNoThrow(try ReportEncoder.jsonString(for: report))
    }

    func testTinyNegativeReadingsAreNotEncodedAsNegativeZero() throws {
        let report = report(snapshot { $0.batteryPowerWatts = -0.001 })
        let battery = try XCTUnwrap(try jsonObject(report)["battery"] as? [String: Any])

        XCTAssertEqual(report.battery.powerWatts, 0)
        XCTAssertEqual(report.battery.powerWatts?.sign, .plus)
        XCTAssertEqual((battery["power_watts"] as? Double)?.sign, .plus)
    }

    func testWarningsAreCarriedIntoTheReport() throws {
        let report = report(snapshot { $0.warnings = ["system_profiler detail read failed"] })
        let object = try jsonObject(report)

        XCTAssertEqual(report.warnings, ["system_profiler detail read failed"])
        XCTAssertEqual(object["warnings"] as? [String], ["system_profiler detail read failed"])
    }

    func testTopReportSortsLimitsAndMarksUnknownMemory() throws {
        let sample = EnergySample(
            consumers: [
                consumer("Slack", cpu: 4.04, memory: 900_000_000),
                consumer("Chrome", cpu: 41.26, memory: 2_000_000_000),
                consumer("WindowServer", cpu: 12.3, memory: 0),
                consumer("Mail", cpu: 4.04, memory: 100_000_000)
            ],
            sampledAt: generatedAt,
            duration: 0.01,
            failed: false,
            isWarmingUp: false
        )

        let report = TopReport(sample: sample, limit: 3, intervalSeconds: 1, generatedAt: generatedAt)

        XCTAssertEqual(report.consumers.map(\.name), ["Chrome", "WindowServer", "Slack"])
        XCTAssertEqual(report.consumers.map(\.cpuPercent), [41.3, 12.3, 4.0])
        XCTAssertEqual(report.consumers[1].memoryBytes, nil)
        XCTAssertEqual(report.consumers[0].memoryBytes, 2_000_000_000)

        let object = try jsonObject(report)
        let rows = try XCTUnwrap(object["consumers"] as? [[String: Any]])
        XCTAssertEqual(Set(object.keys), ["schema_version", "watty_version", "timestamp", "interval_seconds", "consumers"])
        XCTAssertEqual(Set(rows[0].keys), ["name", "cpu_percent", "memory_bytes"])
        XCTAssertTrue(rows[1]["memory_bytes"] is NSNull)
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["interval_seconds"] as? Double, 1)
        XCTAssertEqual(object["timestamp"] as? String, "2026-10-21T16:04:04Z")
    }

    func testTopReportWithNoConsumersEncodesAnEmptyArray() throws {
        let sample = EnergySample(consumers: [], sampledAt: generatedAt, duration: 0, failed: false, isWarmingUp: false)

        let object = try jsonObject(TopReport(sample: sample, limit: 10, intervalSeconds: 1, generatedAt: generatedAt))

        XCTAssertEqual((object["consumers"] as? [Any])?.count, 0)
    }

    func testTopReportLimitNeverGoesNegative() {
        let sample = EnergySample(
            consumers: [consumer("Chrome", cpu: 10, memory: 1)],
            sampledAt: generatedAt,
            duration: 0,
            failed: false,
            isWarmingUp: false
        )

        let report = TopReport(sample: sample, limit: -2, intervalSeconds: 1, generatedAt: generatedAt)

        XCTAssertTrue(report.consumers.isEmpty)
    }

    private func consumer(_ name: String, cpu: Double, memory: UInt64) -> EnergyConsumer {
        EnergyConsumer(id: name, name: name, pid: nil, cpuPercent: cpu, memoryBytes: memory, icon: nil)
    }
}
