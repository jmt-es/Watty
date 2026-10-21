import Darwin
import Foundation

public final class SystemProcessSampler {
    public struct Entry: Equatable {
        public var pid: Int
        public var uid: Int
        public var cpuCentiseconds: UInt64
        public var path: String

        public init(pid: Int, uid: Int, cpuCentiseconds: UInt64, path: String) {
            self.pid = pid
            self.uid = uid
            self.cpuCentiseconds = cpuCentiseconds
            self.path = path
        }
    }

    public static let arguments = ["-A", "-o", "pid=,uid=,cputime=,comm="]
    private static let minimumInterval: TimeInterval = 0.2

    private let excludedUID: Int
    private var previous: [Int: Entry] = [:]
    private var previousUptime: TimeInterval?

    public init(excludedUID: Int = Int(getuid())) {
        self.excludedUID = excludedUID
    }

    public func rows(from output: String, uptime: TimeInterval) -> [ProcessEnergyRow]? {
        let entries = Self.parse(output).filter { $0.uid != excludedUID }
        let current = Dictionary(entries.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        defer {
            previous = current
            previousUptime = uptime
        }
        guard let previousUptime, !previous.isEmpty else { return nil }
        let elapsed = uptime - previousUptime
        guard elapsed >= Self.minimumInterval else { return nil }
        return Self.rows(from: previous, to: current, elapsed: elapsed)
    }

    static func rows(from before: [Int: Entry], to after: [Int: Entry], elapsed: TimeInterval) -> [ProcessEnergyRow] {
        var rows: [ProcessEnergyRow] = []
        for (pid, entry) in after {
            guard let earlier = before[pid], entry.cpuCentiseconds >= earlier.cpuCentiseconds else { continue }
            let cpu = Double(entry.cpuCentiseconds - earlier.cpuCentiseconds) / 100 / elapsed * 100
            guard cpu >= ProcessEnergySampler.minimumCPUPercent else { continue }
            rows.append(ProcessEnergyRow(
                pid: pid,
                command: (entry.path as NSString).lastPathComponent,
                cpuPercent: cpu,
                memoryBytes: 0,
                executablePath: entry.path
            ))
        }
        return rows
    }

    public static func parse(_ output: String) -> [Entry] {
        output.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4,
                  let pid = Int(parts[0]),
                  let uid = Int(parts[1]),
                  let centiseconds = centiseconds(from: String(parts[2])) else {
                return nil
            }
            return Entry(pid: pid, uid: uid, cpuCentiseconds: centiseconds, path: String(parts[3]))
        }
    }

    public static func centiseconds(from cputime: String) -> UInt64? {
        var days: UInt64 = 0
        var clock = cputime
        if let dash = clock.firstIndex(of: "-") {
            guard let value = UInt64(clock[..<dash]) else { return nil }
            days = value
            clock = String(clock[clock.index(after: dash)...])
        }
        let fields = clock.split(separator: ":").map(String.init)
        guard (1...3).contains(fields.count), let seconds = Double(fields[fields.count - 1]) else { return nil }
        var total = days * 86_400
        if fields.count == 3 {
            guard let hours = UInt64(fields[0]), let minutes = UInt64(fields[1]) else { return nil }
            total += hours * 3_600 + minutes * 60
        } else if fields.count == 2 {
            guard let minutes = UInt64(fields[0]) else { return nil }
            total += minutes * 60
        }
        return total * 100 + UInt64((seconds * 100).rounded())
    }
}
