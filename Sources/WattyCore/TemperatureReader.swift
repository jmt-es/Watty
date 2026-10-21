import Foundation
import IOKit
import os

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: AnyObject, _ field: Int32) -> Double

public struct TemperatureReadings: Equatable {
    public var socMaxCelsius: Double?
    public var socAverageCelsius: Double?
    public var sensorCount: Int

    public init(socMaxCelsius: Double?, socAverageCelsius: Double?, sensorCount: Int) {
        self.socMaxCelsius = socMaxCelsius
        self.socAverageCelsius = socAverageCelsius
        self.sensorCount = sensorCount
    }

    static let plausibleRange = 0.0...150.0
    static let dieSensorMarkers = ["tdie", "mtr temp sensor", "pacc", "eacc", "gpu"]

    static func isDieSensor(named name: String) -> Bool {
        let lowercased = name.lowercased()
        return dieSensorMarkers.contains { lowercased.contains($0) }
    }

    public static func summarize(_ sensors: [(name: String, celsius: Double)]) -> TemperatureReadings {
        let dieValues = sensors
            .filter { plausibleRange.contains($0.celsius) && isDieSensor(named: $0.name) }
            .map(\.celsius)
        guard !dieValues.isEmpty else {
            return TemperatureReadings(socMaxCelsius: nil, socAverageCelsius: nil, sensorCount: 0)
        }
        return TemperatureReadings(
            socMaxCelsius: dieValues.max(),
            socAverageCelsius: dieValues.reduce(0, +) / Double(dieValues.count),
            sensorCount: dieValues.count
        )
    }
}

public final class TemperatureReader {
    static let missingSensorsRetryInterval: TimeInterval = 300

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField = Int32(temperatureEventType << 16)
    private static let sensorUsagePage = 0xff00
    private static let temperatureUsage = 5
    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "temperature")

    struct SensorConnection {
        let readSensors: () -> [(name: String, celsius: Double)]
    }

    private let connect: () -> SensorConnection?
    private let uptime: () -> TimeInterval
    private var connection: SensorConnection?
    private var retryNotBefore: TimeInterval?

    public convenience init() {
        self.init(connect: TemperatureReader.connectToHIDSensors, uptime: { ProcessInfo.processInfo.systemUptime })
    }

    init(connect: @escaping () -> SensorConnection?, uptime: @escaping () -> TimeInterval) {
        self.connect = connect
        self.uptime = uptime
    }

    public func read() -> TemperatureReadings? {
        guard let connection = activeConnection() else { return nil }
        return TemperatureReadings.summarize(connection.readSensors())
    }

    private func activeConnection() -> SensorConnection? {
        if let connection { return connection }
        let now = uptime()
        if let retryNotBefore, now < retryNotBefore { return nil }
        guard let found = connect() else {
            retryNotBefore = now + Self.missingSensorsRetryInterval
            Self.logger.info("No HID temperature sensors found, retrying in \(Self.missingSensorsRetryInterval, format: .fixed(precision: 0)) s")
            return nil
        }
        connection = found
        retryNotBefore = nil
        return found
    }

    private static func connectToHIDSensors() -> SensorConnection? {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let matching: [String: Any] = ["PrimaryUsagePage": sensorUsagePage, "PrimaryUsage": temperatureUsage]
        _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return nil
        }

        let dieSensors = services.compactMap { service -> (service: AnyObject, name: String)? in
            let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            return TemperatureReadings.isDieSensor(named: name) ? (service, name) : nil
        }
        guard !dieSensors.isEmpty else { return nil }

        return SensorConnection {
            withExtendedLifetime(client) {
                dieSensors.compactMap { sensor in
                    guard let event = IOHIDServiceClientCopyEvent(sensor.service, temperatureEventType, 0, 0)?.takeRetainedValue() else {
                        return nil
                    }
                    return (name: sensor.name, celsius: IOHIDEventGetFloatValue(event, temperatureField))
                }
            }
        }
    }
}
