import AppKit
import Foundation
import UniformTypeIdentifiers
import WattyCore

enum DemoEnergy {
    struct Application: Equatable {
        let identifier: String
        let name: String
        let bundlePaths: [String]
        let cpuPercent: Double
        let memoryMebibytes: UInt64
    }

    static let sampleDuration: TimeInterval = 1

    static let applications = [
        Application(
            identifier: "com.apple.Safari",
            name: "Safari",
            bundlePaths: ["/Applications/Safari.app", "/System/Cryptexes/App/System/Applications/Safari.app"],
            cpuPercent: 41,
            memoryMebibytes: 1_884
        ),
        Application(
            identifier: "com.apple.Photos",
            name: "Photos",
            bundlePaths: ["/System/Applications/Photos.app"],
            cpuPercent: 14,
            memoryMebibytes: 942
        ),
        Application(
            identifier: "com.apple.Music",
            name: "Music",
            bundlePaths: ["/System/Applications/Music.app"],
            cpuPercent: 7.4,
            memoryMebibytes: 388
        ),
        Application(
            identifier: "com.apple.mail",
            name: "Mail",
            bundlePaths: ["/System/Applications/Mail.app"],
            cpuPercent: 2.8,
            memoryMebibytes: 471
        ),
        Application(
            identifier: "com.apple.MobileSMS",
            name: "Messages",
            bundlePaths: ["/System/Applications/Messages.app"],
            cpuPercent: 1.3,
            memoryMebibytes: 214
        ),
        Application(
            identifier: "com.apple.finder",
            name: "Finder",
            bundlePaths: ["/System/Library/CoreServices/Finder.app"],
            cpuPercent: 0.7,
            memoryMebibytes: 123
        )
    ]

    static let systemProcessName = "WindowServer"
    static let systemProcessCPUPercent = 22.0

    private static let bytesPerMebibyte: UInt64 = 1_048_576

    private static func loadFactor(for scenario: DemoScenario) -> Double {
        switch scenario {
        case .charging: return 1
        case .battery: return 0.55
        case .draining: return 1.6
        case .desktop: return 0.4
        }
    }

    static func sample(for scenario: DemoScenario, at date: Date) -> EnergySample {
        let factor = loadFactor(for: scenario)
        let applicationConsumers = applications.map { application in
            EnergyConsumer(
                id: application.identifier,
                name: application.name,
                pid: nil,
                cpuPercent: application.cpuPercent * factor,
                memoryBytes: application.memoryMebibytes * bytesPerMebibyte,
                icon: icon(forBundlePaths: application.bundlePaths)
            )
        }
        let systemConsumer = EnergyConsumer(
            id: systemProcessName,
            name: systemProcessName,
            pid: nil,
            cpuPercent: systemProcessCPUPercent * factor,
            memoryBytes: 0,
            icon: NSWorkspace.shared.icon(for: .unixExecutable)
        )

        return EnergySample(
            consumers: (applicationConsumers + [systemConsumer]).sorted { $0.cpuPercent > $1.cpuPercent },
            sampledAt: date,
            duration: sampleDuration,
            failed: false,
            isWarmingUp: false
        )
    }

    static func existingBundlePath(in paths: [String]) -> String? {
        paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    // The icon of a symlinked bundle path carries the alias arrow.
    private static func icon(forBundlePaths paths: [String]) -> NSImage? {
        guard let path = existingBundlePath(in: paths) else { return nil }
        return NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }
}
