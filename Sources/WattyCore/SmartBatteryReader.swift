import Foundation
import IOKit
import os

public enum SmartBatteryReadResult {
    case properties([String: Any])
    case noService
    case failed(String)

    public var properties: [String: Any]? {
        if case .properties(let properties) = self { return properties }
        return nil
    }

    public var serviceExists: Bool {
        if case .noService = self { return false }
        return true
    }
}

public enum SmartBatteryReader {
    public static let serviceName = "AppleSmartBattery"
    public static let childrenKey = "IORegistryChildren"

    static let maximumDescendantDepth = 2
    static let maximumIteratorAttempts = 3

    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "smart-battery")

    private enum PropertyFailure: Error, CustomStringConvertible {
        case status(kern_return_t)
        case notADictionary

        var description: String {
            switch self {
            case .status(let status): return "IORegistryEntryCreateCFProperties failed with status \(status)"
            case .notADictionary: return "registry properties were not a dictionary"
            }
        }
    }

    public static func read() -> SmartBatteryReadResult {
        guard let matching = IOServiceMatching(serviceName) else {
            logger.error("IOServiceMatching returned no dictionary for \(serviceName, privacy: .public)")
            return .failed("IOServiceMatching returned no dictionary")
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return .noService }
        defer { IOObjectRelease(service) }

        switch copyProperties(of: service) {
        case .failure(let failure):
            return .failed(failure.description)
        case .success(var properties):
            let descendants = copyDescendants(of: service, remainingDepth: maximumDescendantDepth)
            if !descendants.isEmpty {
                properties[childrenKey] = descendants
            }
            return .properties(properties)
        }
    }

    // Recent Macs keep Temperature only in the child AppleSmartBatteryPack node, which `ioreg -r` prints as part of the subtree.
    private static func copyDescendants(of entry: io_registry_entry_t, remainingDepth: Int) -> [[String: Any]] {
        guard remainingDepth > 0 else { return [] }
        var iterator = io_iterator_t()
        let status = IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator)
        guard status == KERN_SUCCESS else {
            logger.error("IORegistryEntryGetChildIterator failed with status \(status)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        var children: [[String: Any]] = []
        for _ in 0..<maximumIteratorAttempts {
            children = []
            while case let child = IOIteratorNext(iterator), child != 0 {
                defer { IOObjectRelease(child) }
                switch copyProperties(of: child) {
                case .failure(let failure):
                    logger.error("Child registry entry unreadable: \(failure.description, privacy: .public)")
                case .success(var properties):
                    let grandchildren = copyDescendants(of: child, remainingDepth: remainingDepth - 1)
                    if !grandchildren.isEmpty {
                        properties[childrenKey] = grandchildren
                    }
                    children.append(properties)
                }
            }
            if IOIteratorIsValid(iterator) != 0 { break }
            IOIteratorReset(iterator)
        }
        return children
    }

    private static func copyProperties(of entry: io_registry_entry_t) -> Result<[String: Any], PropertyFailure> {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() else {
            return .failure(.status(status))
        }
        guard let dictionary = properties as? [String: Any] else { return .failure(.notADictionary) }
        return .success(dictionary)
    }
}
