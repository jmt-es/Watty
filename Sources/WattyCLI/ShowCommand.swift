import Foundation
import WattyCore

enum ShowCommand {
    static let readinessTimeout: TimeInterval = 10
    static let installHint = "Install it with 'brew install jmt-es/tap/watty' and try again."

    static func run(context: CommandContext) async -> Int32 {
        let bundleIdentifier = WattyVersion.bundleIdentifier
        let launcher = context.launcher

        if launcher.isRunning(bundleIdentifier: bundleIdentifier) {
            launcher.postShowRequest()
            return ExitCode.success
        }

        guard let applicationURL = launcher.applicationURL(bundleIdentifier: bundleIdentifier) else {
            return context.reportFailure(
                "Watty.app is not installed (no application with bundle identifier \(bundleIdentifier) was found). \(installHint)"
            )
        }

        do {
            try await launcher.launch(applicationAt: applicationURL)
        } catch {
            return context.reportFailure("could not open \(applicationURL.path): \(error.localizedDescription)")
        }

        guard await launcher.waitUntilReady(bundleIdentifier: bundleIdentifier, timeout: readinessTimeout) else {
            return context.reportFailure(
                "Watty was started but did not finish launching within \(Int(readinessTimeout)) s; open it from the menu bar instead."
            )
        }
        launcher.postShowRequest()
        return ExitCode.success
    }
}
