import Darwin
import Foundation
import os

public struct ProcessEnergyRow: Equatable {
    public var pid: Int
    public var command: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var executablePath: String?

    public init(pid: Int, command: String, cpuPercent: Double, memoryBytes: UInt64, executablePath: String? = nil) {
        self.pid = pid
        self.command = command
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.executablePath = executablePath
    }
}

public final class ProcessEnergySampler {
    struct Reading: Equatable {
        var cpuTicks: UInt64
        var footprintBytes: UInt64
    }

    public static let minimumCPUPercent = 0.2
    private static let minimumInterval: TimeInterval = 0.2
    private static let pidCapacity = 16_384
    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "energy")

    static let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return 1 }
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    private var previous: [pid_t: Reading] = [:]
    private var previousUptime: TimeInterval?

    public init() {}

    public var isWarmedUp: Bool {
        previousUptime != nil
    }

    public func sample() -> [ProcessEnergyRow]? {
        let uptime = ProcessInfo.processInfo.systemUptime
        let current = Self.readAll()
        defer {
            previous = current
            previousUptime = uptime
        }
        guard let previousUptime, !previous.isEmpty else { return nil }
        let elapsed = uptime - previousUptime
        guard elapsed >= Self.minimumInterval else { return nil }
        return Self.rows(from: previous, to: current, elapsed: elapsed, nanosecondsPerTick: Self.nanosecondsPerTick)
    }

    static func rows(
        from before: [pid_t: Reading],
        to after: [pid_t: Reading],
        elapsed: TimeInterval,
        nanosecondsPerTick: Double
    ) -> [ProcessEnergyRow] {
        var rows: [ProcessEnergyRow] = []
        for (pid, reading) in after {
            guard let earlier = before[pid], reading.cpuTicks >= earlier.cpuTicks else { continue }
            let cpuSeconds = Double(reading.cpuTicks - earlier.cpuTicks) * nanosecondsPerTick / 1e9
            let cpu = cpuSeconds / elapsed * 100
            guard cpu >= minimumCPUPercent else { continue }
            rows.append(ProcessEnergyRow(
                pid: Int(pid),
                command: processName(pid),
                cpuPercent: cpu,
                memoryBytes: reading.footprintBytes
            ))
        }
        return rows
    }

    private static func readAll() -> [pid_t: Reading] {
        var pids = [pid_t](repeating: 0, count: pidCapacity)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else {
            logger.error("proc_listallpids returned \(count)")
            return [:]
        }

        var readings: [pid_t: Reading] = [:]
        for pid in pids.prefix(min(count, pids.count)) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }
            readings[pid] = Reading(
                cpuTicks: info.ri_user_time &+ info.ri_system_time,
                footprintBytes: info.ri_phys_footprint
            )
        }
        return readings
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }
}
