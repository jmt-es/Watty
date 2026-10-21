import Darwin
import Foundation
import os

public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    public var total: UInt64 {
        user &+ system &+ idle &+ nice
    }
}

public struct CPUUsage: Equatable {
    public var userPercent: Double
    public var systemPercent: Double

    public init(userPercent: Double, systemPercent: Double) {
        self.userPercent = userPercent
        self.systemPercent = systemPercent
    }

    public var totalPercent: Double {
        min(100, userPercent + systemPercent)
    }

    public static func between(_ previous: CPUTicks, _ current: CPUTicks) -> CPUUsage? {
        let total = current.total &- previous.total
        guard total > 0, current.total >= previous.total else { return nil }
        let user = Double((current.user &+ current.nice) &- (previous.user &+ previous.nice))
        let system = Double(current.system &- previous.system)
        return CPUUsage(
            userPercent: user / Double(total) * 100,
            systemPercent: system / Double(total) * 100
        )
    }
}

public struct MemoryUsage: Equatable {
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public var swapUsedBytes: UInt64

    public init(
        usedBytes: UInt64,
        appBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        totalBytes: UInt64,
        swapUsedBytes: UInt64
    ) {
        self.usedBytes = usedBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes
    }

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes) / Double(totalBytes) * 100)
    }

    public static func from(
        internalPages: UInt64,
        purgeablePages: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64,
        pageSize: UInt64,
        totalBytes: UInt64,
        swapUsedBytes: UInt64
    ) -> MemoryUsage {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        let app = appPages * pageSize
        let wired = wiredPages * pageSize
        let compressed = compressorPages * pageSize
        return MemoryUsage(
            usedBytes: app + wired + compressed,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            totalBytes: totalBytes,
            swapUsedBytes: swapUsedBytes
        )
    }
}

public struct SystemStats: Equatable {
    public var date: Date
    public var cpu: CPUUsage?
    public var memory: MemoryUsage?
    public var temperature: TemperatureReadings?

    public init(date: Date, cpu: CPUUsage?, memory: MemoryUsage?, temperature: TemperatureReadings?) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.temperature = temperature
    }
}

public final class SystemStatsSampler {
    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "stats")

    private var previousTicks: CPUTicks?
    private let temperatureReader = TemperatureReader()
    private let pageSize = UInt64(vm_kernel_page_size)
    private let totalBytes = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func sample() -> SystemStats {
        let ticks = Self.readCPUTicks()
        var cpu: CPUUsage?
        if let ticks, let previousTicks {
            cpu = CPUUsage.between(previousTicks, ticks)
        }
        if let ticks {
            previousTicks = ticks
        }

        return SystemStats(
            date: Date(),
            cpu: cpu,
            memory: readMemory(),
            temperature: temperatureReader.read()
        )
    }

    static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            logger.error("host_statistics(HOST_CPU_LOAD_INFO) failed status=\(result)")
            return nil
        }
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private func readMemory() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            Self.logger.error("host_statistics64(HOST_VM_INFO64) failed status=\(result)")
            return nil
        }

        return MemoryUsage.from(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressorPages: UInt64(stats.compressor_page_count),
            pageSize: pageSize,
            totalBytes: totalBytes,
            swapUsedBytes: Self.readSwapUsed()
        )
    }

    private static func readSwapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else {
            logger.error("sysctl vm.swapusage failed errno=\(errno)")
            return 0
        }
        return usage.xsu_used
    }
}
