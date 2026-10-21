import os
import WattyCore

enum AppLog {
    static func logger(_ category: String) -> Logger {
        Logger(subsystem: WattyVersion.bundleIdentifier, category: category)
    }
}
