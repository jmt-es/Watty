import AppKit
import Foundation

protocol AppLauncher {
    func isRunning(bundleIdentifier: String) -> Bool
    func postShowRequest()
    func applicationURL(bundleIdentifier: String) -> URL?
    func launch(applicationAt url: URL) async throws
    func waitUntilReady(bundleIdentifier: String, timeout: TimeInterval) async -> Bool
}

final class WorkspaceAppLauncher: AppLauncher {
    static let showNotificationName = "com.jmtes.watty.show"

    private static let readinessPollNanoseconds: UInt64 = 100_000_000
    private static let postLaunchSettleNanoseconds: UInt64 = 500_000_000

    init() {}

    func isRunning(bundleIdentifier: String) -> Bool {
        !runningApplications(bundleIdentifier: bundleIdentifier).isEmpty
    }

    func postShowRequest() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Self.showNotificationName),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func launch(applicationAt url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func waitUntilReady(bundleIdentifier: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningApplications(bundleIdentifier: bundleIdentifier).contains(where: \.isFinishedLaunching) {
                try? await Task.sleep(nanoseconds: Self.postLaunchSettleNanoseconds)
                return true
            }
            try? await Task.sleep(nanoseconds: Self.readinessPollNanoseconds)
        }
        return false
    }

    private func runningApplications(bundleIdentifier: String) -> [NSRunningApplication] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
    }
}
