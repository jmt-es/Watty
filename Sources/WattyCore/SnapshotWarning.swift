import Foundation

public enum SnapshotWarning: String, CaseIterable, Equatable {
    case powerSourceReadFailed = "IOKit power source read failed"
    case smartBatteryReadFailed = "AppleSmartBattery read failed"
    case ioregBatteryReadFailed = "ioreg battery read failed"
    case pmsetBatteryReadFailed = "pmset battery read failed"
    case pmsetSettingsReadFailed = "pmset settings read failed"
    case systemProfilerDetailReadFailed = "system_profiler detail read failed"

    public var message: String {
        rawValue
    }
}
