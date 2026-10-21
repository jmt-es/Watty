import AppKit
import Foundation
import os

public enum SnapshotDepth: Equatable {
    case essentials
    case full
}

public final class BatteryService: TelemetryProviding {
    public static let shared = BatteryService()

    private struct BatteryReadings {
        var hasBattery: Bool
        var powerSource: PowerSourceInfo?
        var registry: IoregBatteryInfo
        var pmsetBattery: PmsetBatteryInfo?
    }

    private enum Tool {
        static let ioreg = "/usr/sbin/ioreg"
        static let pmset = "/usr/bin/pmset"
        static let osascript = "/usr/bin/osascript"
        static let ps = "/bin/ps"
        static let ioregTimeout: TimeInterval = 2
        static let pmsetTimeout: TimeInterval = 2
        static let osascriptTimeout: TimeInterval = 120
        static let psTimeout: TimeInterval = 3
    }

    private let dependencies: BatteryServiceDependencies
    private let configuration: PowerConfigurationProvider
    private let telemetryQueue = DispatchQueue(label: "com.jmtes.watty.telemetry", qos: .userInitiated)
    private let energyQueue = DispatchQueue(label: "com.jmtes.watty.energy", qos: .utility)
    private let actionQueue = DispatchQueue(label: "com.jmtes.watty.actions", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.jmtes.watty", category: "service")
    private static let userCanceledCode = "(-128)"
    public static let maximumEnergyConsumers = 25
    private let statsSampler = SystemStatsSampler()
    private let energySampler = ProcessEnergySampler()
    private let systemProcessSampler = SystemProcessSampler()
    private var identityCache: [Int: ProcessIdentity] = [:]
    private var lastSmartBatteryFailure: String?

    public convenience init(detailsLifetime: TimeInterval = 300) {
        self.init(detailsLifetime: detailsLifetime, dependencies: .live)
    }

    init(detailsLifetime: TimeInterval, dependencies: BatteryServiceDependencies) {
        self.dependencies = dependencies
        configuration = PowerConfigurationProvider(
            runner: dependencies.runner,
            now: dependencies.now,
            detailsLifetime: detailsLifetime
        )
    }

    public func fetchSnapshot(depth: SnapshotDepth = .full, forceDetails: Bool = false) async -> BatterySnapshot {
        await perform(on: telemetryQueue) { self.readSnapshot(depth: depth, forceDetails: forceDetails) }
    }

    public func fetchSystemStats() async -> SystemStats {
        await perform(on: telemetryQueue) { self.statsSampler.sample() }
    }

    public func fetchEnergySample() async -> EnergySample {
        await perform(on: energyQueue) { self.sampleEnergy() }
    }

    public func setPowerMode(_ mode: PowerMode) async -> ServiceActionResult {
        await perform(on: actionQueue) { self.applyPowerMode(mode) }
    }

    public func openBatterySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Battery-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.energysaver"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
        logger.error("No battery settings URL could be opened")
    }

    private func perform<T>(on queue: DispatchQueue, _ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    private func readSnapshot(depth: SnapshotDepth, forceDetails: Bool) -> BatterySnapshot {
        let startedAt = Date()
        var warnings: [String] = []

        let battery = readBattery(depth: depth, warnings: &warnings)
        let settings = configuration.settings(depth: depth, warnings: &warnings)
        let support = PowerModeSupport(capabilities: configuration.capabilities(), settings: settings)

        let powerSource = battery.powerSource
        let registry = battery.registry
        let pmsetBattery = battery.pmsetBattery
        let lowPowerModeActive = powerSource?.lowPowerModeActive ?? ProcessInfo.processInfo.isLowPowerModeEnabled

        let modeNeedsDetails = settings.resolvedMode == nil && !lowPowerModeActive
        let details = battery.hasBattery || modeNeedsDetails
            ? configuration.details(depth: depth, force: forceDetails, warnings: &warnings)
            : nil

        let externalConnected = !battery.hasBattery
            || (powerSource?.externalPower ?? registry.externalConnected ?? (pmsetBattery?.powerSource == .adapter))
        let isCharging = powerSource?.isCharging ?? registry.isCharging ?? pmsetBattery?.isCharging ?? false
        let isFullyCharged = powerSource?.isCharged ?? registry.isFullyCharged ?? pmsetBattery?.isFullyCharged ?? false
        let level = max(0, min(100, powerSource?.level ?? registry.currentCapacityPercent ?? pmsetBattery?.level ?? 0))

        let powerMode = Self.resolvedPowerMode(settings: settings, lowPowerModeActive: lowPowerModeActive, details: details)

        let snapshot = BatterySnapshot(
            hasBattery: battery.hasBattery,
            level: level,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            isFinishingCharge: powerSource?.isFinishingCharge ?? false,
            powerSource: externalConnected ? .adapter : .battery,
            timeToFullMinutes: powerSource?.timeToFullMinutes ?? registry.timeToFullMinutes ?? (isCharging ? pmsetBattery?.timeRemainingMinutes : nil),
            timeToEmptyMinutes: powerSource?.timeToEmptyMinutes ?? registry.timeToEmptyMinutes ?? (isCharging ? nil : pmsetBattery?.timeRemainingMinutes),
            voltageVolts: registry.voltageVolts,
            amperageAmps: PowerReadingSanitizer.batteryFlow(registry.amperageAmps, onExternalPower: externalConnected),
            batteryPowerWatts: PowerReadingSanitizer.batteryFlow(registry.batteryPowerWatts, onExternalPower: externalConnected),
            systemPowerWatts: registry.systemPowerWatts,
            systemLoadWatts: PowerReadingSanitizer.systemLoad(registry.systemLoadWatts),
            adapterRatedWatts: details?.adapterRatedWatts ?? registry.adapterRatedWatts,
            adapterDescription: registry.adapterDescription,
            cycleCount: details?.cycleCount ?? registry.cycleCount,
            condition: details?.condition,
            maximumCapacityPercent: details?.maximumCapacityPercent ?? registry.maximumCapacityPercent,
            temperatureCelsius: registry.temperatureCelsius,
            powerMode: powerMode,
            lowPowerModeActive: lowPowerModeActive,
            powerModeSupport: support,
            readDuration: Date().timeIntervalSince(startedAt),
            lastUpdated: Date(),
            warnings: warnings
        )

        logger.debug("snapshot depth=\(depth == .full ? "full" : "essentials", privacy: .public) battery=\(battery.hasBattery) level=\(level) charging=\(isCharging) mode=\(powerMode?.title ?? "?", privacy: .public) took=\(snapshot.readDuration * 1000, format: .fixed(precision: 0))ms warnings=\(warnings.count)")
        return snapshot
    }

    private static func resolvedPowerMode(
        settings: PmsetSettingsInfo,
        lowPowerModeActive: Bool,
        details: SystemProfilerPowerInfo?
    ) -> PowerMode? {
        if let mode = settings.resolvedMode { return mode }
        if lowPowerModeActive { return .lowPower }
        guard let details else { return nil }
        return details.highPowerMode == true ? .highPower : (details.lowPowerMode == true ? .lowPower : .automatic)
    }

    private func readBattery(depth: SnapshotDepth, warnings: inout [String]) -> BatteryReadings {
        let powerSourceResult = dependencies.readPowerSource()
        let smartBatteryResult = dependencies.readSmartBattery()
        let powerSource = powerSourceResult.internalBattery

        guard powerSource != nil || smartBatteryResult.serviceExists else {
            if case .unavailable = powerSourceResult {
                logger.notice("IOKit power sources unavailable and no AppleSmartBattery service, reporting no battery")
            }
            return BatteryReadings(hasBattery: false, powerSource: nil, registry: IoregBatteryInfo(), pmsetBattery: nil)
        }

        if case .unavailable = powerSourceResult {
            warnings.append(SnapshotWarning.powerSourceReadFailed.message)
            logger.error("IOKit power source read failed while a battery is present")
        }

        let registry = readRegistry(smartBatteryResult, depth: depth, warnings: &warnings)

        var pmsetBattery: PmsetBatteryInfo?
        if depth == .full, powerSource == nil, registry.currentCapacityPercent == nil {
            pmsetBattery = readPmsetBattery(warnings: &warnings)
        }
        return BatteryReadings(hasBattery: true, powerSource: powerSource, registry: registry, pmsetBattery: pmsetBattery)
    }

    private func readRegistry(
        _ result: SmartBatteryReadResult,
        depth: SnapshotDepth,
        warnings: inout [String]
    ) -> IoregBatteryInfo {
        switch result {
        case .properties(let properties):
            recordSmartBattery(failure: nil)
            return TelemetryParsers.parseSmartBatteryProperties(properties)
        case .noService:
            recordSmartBattery(failure: nil)
            return IoregBatteryInfo()
        case .failed(let reason):
            recordSmartBattery(failure: reason)
            guard depth == .full else {
                warnings.append(SnapshotWarning.smartBatteryReadFailed.message)
                return IoregBatteryInfo()
            }
            return readRegistryWithIoreg(warnings: &warnings)
        }
    }

    private func readRegistryWithIoreg(warnings: inout [String]) -> IoregBatteryInfo {
        let result = dependencies.runner.run(
            Tool.ioreg,
            arguments: ["-l", "-n", SmartBatteryReader.serviceName, "-r"],
            timeout: Tool.ioregTimeout
        )
        guard result.succeeded else {
            warnings.append(SnapshotWarning.ioregBatteryReadFailed.message)
            logger.logCommandFailure("ioreg \(SmartBatteryReader.serviceName)", result)
            return IoregBatteryInfo()
        }
        return TelemetryParsers.parseIoregBattery(result.stdout)
    }

    private func readPmsetBattery(warnings: inout [String]) -> PmsetBatteryInfo? {
        let result = dependencies.runner.run(Tool.pmset, arguments: ["-g", "batt"], timeout: Tool.pmsetTimeout)
        guard result.succeeded else {
            warnings.append(SnapshotWarning.pmsetBatteryReadFailed.message)
            logger.logCommandFailure("pmset -g batt", result)
            return nil
        }
        return TelemetryParsers.parsePmsetBattery(result.stdout)
    }

    private func recordSmartBattery(failure: String?) {
        guard failure != lastSmartBatteryFailure else { return }
        if let failure {
            logger.error("AppleSmartBattery in-process read failed: \(failure, privacy: .public)")
        } else {
            logger.notice("AppleSmartBattery in-process read recovered")
        }
        lastSmartBatteryFailure = failure
    }

    private func sampleEnergy() -> EnergySample {
        let startedAt = Date()
        let userRows = energySampler.sample()
        let psResult = dependencies.runner.run(Tool.ps, arguments: SystemProcessSampler.arguments, timeout: Tool.psTimeout)
        let systemRows = psResult.succeeded
            ? systemProcessSampler.rows(from: psResult.stdout, uptime: ProcessInfo.processInfo.systemUptime)
            : nil
        if !psResult.succeeded {
            logger.error("ps sample failed status=\(psResult.terminationStatus)")
        }
        guard userRows != nil || systemRows != nil else {
            return EnergySample(consumers: [], sampledAt: Date(), duration: Date().timeIntervalSince(startedAt), failed: false, isWarmingUp: true)
        }
        let rows = (userRows ?? []) + (systemRows ?? [])

        var identities: [Int: ProcessIdentity] = [:]
        let aggregated = TelemetryParsers.aggregateEnergy(rows) { row in
            let identity = identityCache[row.pid]
                ?? ProcessIdentityResolver.resolve(pid: row.pid, command: row.command, knownPath: row.executablePath)
            identities[row.pid] = identity
            return EnergyIdentity(key: identity.key, name: identity.name)
        }
        identityCache = identities

        let consumers = aggregated.prefix(Self.maximumEnergyConsumers).map { process in
            EnergyConsumer(
                id: process.key,
                name: process.name,
                pid: process.pids.first,
                cpuPercent: process.cpuPercent,
                memoryBytes: process.memoryBytes,
                icon: process.pids.first.flatMap { identities[$0]?.icon }
            )
        }

        let sample = EnergySample(
            consumers: Array(consumers),
            sampledAt: Date(),
            duration: Date().timeIntervalSince(startedAt),
            failed: false,
            isWarmingUp: false
        )
        logger.debug("energy sample rows=\(rows.count) consumers=\(sample.consumers.count) took=\(sample.duration * 1000, format: .fixed(precision: 1))ms")
        return sample
    }

    private func applyPowerMode(_ mode: PowerMode) -> ServiceActionResult {
        var warnings: [String] = []
        let settings = configuration.readSettings(warnings: &warnings) ?? PmsetSettingsInfo()
        let support = PowerModeSupport(capabilities: configuration.capabilities(), settings: settings)
        let script = mode.shellScript(support: support)
        let appleScript = "do shell script \"\(script.escapedForAppleScript)\" with administrator privileges"
        logger.info("applying power mode \(mode.title, privacy: .public) via \(script, privacy: .public)")

        let result = dependencies.runner.run(Tool.osascript, arguments: ["-e", appleScript], timeout: Tool.osascriptTimeout)
        let resultingMode = configuration.readSettings(warnings: &warnings)?.resolvedMode
        configuration.invalidateSettings()

        if result.succeeded {
            if let resultingMode, resultingMode != mode {
                return ServiceActionResult(reason: .systemKeptMode(resultingMode), resultingMode: resultingMode)
            }
            return ServiceActionResult(reason: .applied(mode), resultingMode: resultingMode ?? mode)
        }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason: ServiceActionReason
        if stderr.contains(Self.userCanceledCode) || stderr.localizedCaseInsensitiveContains("User canceled") {
            reason = .canceled
        } else if result.didTimeOut {
            reason = .timedOut
        } else {
            reason = .failed(detail: stderr.isEmpty ? nil : stderr)
        }
        let failure = ServiceActionResult(reason: reason, resultingMode: resultingMode)
        logger.error("power mode change failed: \(failure.message, privacy: .public)")
        return failure
    }
}

private extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
