import Foundation
import os

public struct BatteryHistorySample: Codable, Equatable, Identifiable {
    public let date: Date
    public let level: Int
    public let isCharging: Bool
    public let onAdapter: Bool

    public var id: Date { date }

    public init(date: Date, level: Int, isCharging: Bool, onAdapter: Bool) {
        self.date = date
        self.level = min(100, max(0, level))
        self.isCharging = isCharging
        self.onAdapter = onAdapter
    }
}

public struct BatteryHistory: Equatable {
    public static let retention: TimeInterval = 24 * 60 * 60
    public static let minimumInterval: TimeInterval = 60
    public static let maximumSamples = 4_000
    public static let futureTolerance: TimeInterval = 120

    public private(set) var samples: [BatteryHistorySample]

    public init(samples: [BatteryHistorySample] = []) {
        self.samples = samples
    }

    @discardableResult
    public mutating func record(_ sample: BatteryHistorySample) -> Bool {
        var changed = false
        while let last = samples.last, last.date > sample.date {
            samples.removeLast()
            changed = true
        }

        if let last = samples.last {
            guard sample.date > last.date else { return changed }
            let stateChanged = last.level != sample.level
                || last.isCharging != sample.isCharging
                || last.onAdapter != sample.onAdapter
            let intervalElapsed = sample.date.timeIntervalSince(last.date) >= Self.minimumInterval
            guard stateChanged || intervalElapsed else { return changed }
        }

        samples.append(sample)
        prune(now: sample.date)
        return true
    }

    public mutating func prune(now: Date) {
        let oldest = now.addingTimeInterval(-Self.retention)
        let newest = now.addingTimeInterval(Self.futureTolerance)
        samples.removeAll { $0.date < oldest || $0.date > newest }
        if samples.count > Self.maximumSamples {
            samples.removeFirst(samples.count - Self.maximumSamples)
        }
    }

    public func samples(since date: Date) -> [BatteryHistorySample] {
        samples.filter { $0.date >= date }
    }

    static func sanitized(_ samples: [BatteryHistorySample], now: Date) -> BatteryHistory {
        var unique: [BatteryHistorySample] = []
        for sample in samples.sorted(by: { $0.date < $1.date }) where sample.date != unique.last?.date {
            unique.append(BatteryHistorySample(
                date: sample.date,
                level: sample.level,
                isCharging: sample.isCharging,
                onAdapter: sample.onAdapter
            ))
        }
        var history = BatteryHistory(samples: unique)
        history.prune(now: now)
        return history
    }
}

public final class BatteryHistoryStore {
    public static let saveInterval: TimeInterval = 300
    public static let fileFormatVersion = 1
    public static let directoryName = "Watty"
    public static let fileName = "battery-history.json"
    public static let corruptFileName = "battery-history.corrupt.json"

    public static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private struct FileContents: Codable {
        var version: Int
        var samples: [BatteryHistorySample]
    }

    public let fileURL: URL
    public private(set) var history = BatteryHistory()
    public private(set) var isSaveFailing = false

    private let writesEnabled: Bool
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.jmtes.watty", category: "history")
    private var hasUnsavedChanges = false
    private var lastSaveAttempt = Date()

    public init(
        fileURL: URL = BatteryHistoryStore.defaultFileURL,
        writesEnabled: Bool = true,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.writesEnabled = writesEnabled
        self.fileManager = fileManager
    }

    public func load(now: Date = Date()) {
        lastSaveAttempt = now
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.debug("no battery history file yet")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let contents = try Self.decoder.decode(FileContents.self, from: data)
            guard contents.version == Self.fileFormatVersion else {
                throw LoadError.unsupportedVersion(contents.version)
            }
            history = BatteryHistory.sanitized(contents.samples, now: now)
            logger.info("loaded \(self.history.samples.count) battery history samples")
        } catch {
            logger.error("battery history unreadable: \(error.localizedDescription, privacy: .public)")
            setAsideUnreadableFile()
            history = BatteryHistory()
        }
    }

    @discardableResult
    public func record(level: Int, isCharging: Bool, onAdapter: Bool, at date: Date = Date()) -> Bool {
        let sample = BatteryHistorySample(date: date, level: level, isCharging: isCharging, onAdapter: onAdapter)
        let changed = history.record(sample)
        if changed { hasUnsavedChanges = true }
        return changed
    }

    public func saveIfDue(now: Date = Date()) {
        guard hasUnsavedChanges, now.timeIntervalSince(lastSaveAttempt) >= Self.saveInterval else { return }
        write(now: now)
    }

    public func save(now: Date = Date()) {
        guard hasUnsavedChanges else { return }
        write(now: now)
    }

    private enum LoadError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): return "unsupported file version \(version)"
            }
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private func write(now: Date) {
        lastSaveAttempt = now
        guard writesEnabled else { return }

        do {
            let data = try Self.encoder.encode(FileContents(version: Self.fileFormatVersion, samples: history.samples))
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            hasUnsavedChanges = false
            isSaveFailing = false
            logger.debug("saved \(self.history.samples.count) battery history samples")
        } catch {
            isSaveFailing = true
            logger.error("battery history could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setAsideUnreadableFile() {
        guard writesEnabled else { return }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(Self.corruptFileName)
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: fileURL, to: destination)
            logger.error("unreadable battery history moved to \(destination.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("unreadable battery history could not be set aside: \(error.localizedDescription, privacy: .public)")
        }
    }
}
