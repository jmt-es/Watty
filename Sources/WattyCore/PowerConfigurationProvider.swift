import Foundation
import os

final class PowerConfigurationProvider {
    private enum Command {
        static let pmset = "/usr/bin/pmset"
        static let systemProfiler = "/usr/sbin/system_profiler"
        static let settingsArguments = ["-g"]
        static let capabilitiesArguments = ["-g", "cap"]
        static let detailsArguments = ["SPPowerDataType", "-detailLevel", "mini"]
        static let pmsetTimeout: TimeInterval = 2
        static let systemProfilerTimeout: TimeInterval = 12
    }

    private let runner: CommandRunning
    private let now: () -> Date
    private let detailsLifetime: TimeInterval
    private let logger = Logger(subsystem: "com.jmtes.watty", category: "configuration")
    private let lock = NSLock()
    private var settingsCache: PmsetSettingsInfo?
    private var capabilitiesCache: Set<String>?
    private var detailsCache: (info: SystemProfilerPowerInfo, readAt: Date)?

    init(runner: CommandRunning, now: @escaping () -> Date, detailsLifetime: TimeInterval) {
        self.runner = runner
        self.now = now
        self.detailsLifetime = detailsLifetime
    }

    func settings(depth: SnapshotDepth, warnings: inout [String]) -> PmsetSettingsInfo {
        let cached = locked { settingsCache }
        if depth == .essentials, let cached { return cached }
        return readSettings(warnings: &warnings) ?? cached ?? PmsetSettingsInfo()
    }

    func readSettings(warnings: inout [String]) -> PmsetSettingsInfo? {
        let result = runner.run(Command.pmset, arguments: Command.settingsArguments, timeout: Command.pmsetTimeout)
        guard result.succeeded else {
            warnings.append(SnapshotWarning.pmsetSettingsReadFailed.message)
            logger.logCommandFailure("pmset -g", result)
            return nil
        }
        let settings = TelemetryParsers.parsePmsetSettings(result.stdout)
        locked { settingsCache = settings }
        return settings
    }

    func invalidateSettings() {
        locked { settingsCache = nil }
    }

    func capabilities() -> Set<String> {
        if let cached = locked({ capabilitiesCache }) { return cached }
        let result = runner.run(Command.pmset, arguments: Command.capabilitiesArguments, timeout: Command.pmsetTimeout)
        guard result.succeeded else {
            logger.logCommandFailure("pmset -g cap", result)
            return []
        }
        let capabilities = TelemetryParsers.parsePmsetCapabilities(result.stdout)
        locked { capabilitiesCache = capabilities }
        return capabilities
    }

    func details(depth: SnapshotDepth, force: Bool, warnings: inout [String]) -> SystemProfilerPowerInfo? {
        let cached = locked { detailsCache }
        guard depth == .full else { return cached?.info }
        if let cached, !force, now().timeIntervalSince(cached.readAt) < detailsLifetime {
            return cached.info
        }

        let result = runner.run(
            Command.systemProfiler,
            arguments: Command.detailsArguments,
            timeout: Command.systemProfilerTimeout
        )
        guard result.succeeded else {
            warnings.append(SnapshotWarning.systemProfilerDetailReadFailed.message)
            logger.logCommandFailure("system_profiler SPPowerDataType", result)
            return cached?.info
        }
        let info = TelemetryParsers.parseSystemProfilerPower(result.stdout)
        let readAt = now()
        locked { detailsCache = (info, readAt) }
        return info
    }

    private func locked<Value>(_ body: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
