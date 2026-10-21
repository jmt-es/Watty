import AppKit
import Foundation
import UniformTypeIdentifiers

struct ProcessIdentity {
    let key: String
    let name: String
    let icon: NSImage?
}

enum ProcessIdentityResolver {
    static func resolve(pid: Int, command: String, knownPath: String? = nil) -> ProcessIdentity {
        if let path = executablePath(pid: pid) ?? knownPath {
            if let bundlePath = outermostAppBundle(in: path) {
                return bundleIdentity(bundlePath: bundlePath)
            }
            let executableName = (path as NSString).lastPathComponent
            let name = TelemetryParsers.normalizedProcessName(executableName)
            return ProcessIdentity(key: path, name: name, icon: genericIcon)
        }

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           let name = app.localizedName {
            return ProcessIdentity(key: app.bundleIdentifier ?? name, name: name, icon: app.icon)
        }

        let name = TelemetryParsers.normalizedProcessName(command)
        return ProcessIdentity(key: name, name: name, icon: installedAppIcon(named: name))
    }

    static func outermostAppBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func executablePath(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func bundleIdentity(bundlePath: String) -> ProcessIdentity {
        let bundle = Bundle(path: bundlePath)
        let fallbackName = ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackName
        return ProcessIdentity(
            key: bundle?.bundleIdentifier ?? bundlePath,
            name: name,
            icon: NSWorkspace.shared.icon(forFile: bundlePath)
        )
    }

    private static func installedAppIcon(named name: String) -> NSImage? {
        let searchPaths = [
            "/Applications/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app"
        ]
        for path in searchPaths where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return genericIcon
    }

    private static let genericIcon: NSImage = NSWorkspace.shared.icon(for: .unixExecutable)
}
