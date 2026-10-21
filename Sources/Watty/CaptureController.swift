import AppKit
import Foundation
import WattyCore

@MainActor
final class CaptureController {
    enum Failure: Error, LocalizedError {
        case timedOut(waitingFor: [String])
        case windowUnavailable
        case renderFailed
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .timedOut(let missing):
                return "timed out waiting for \(missing.joined(separator: ", "))"
            case .windowUnavailable:
                return "the window to capture did not appear"
            case .renderFailed:
                return "could not render the window to an image"
            case .writeFailed(let url, let error):
                return "could not write \(url.path): \(error.localizedDescription)"
            }
        }
    }

    static let readinessTimeout: TimeInterval = 20
    static let windowTimeout: TimeInterval = 5
    static let pollInterval: Duration = .milliseconds(100)
    static let settleDelay: Duration = .milliseconds(900)
    static let outputScale: CGFloat = 2
    static let failureExitCode: Int32 = 1

    private static let settingsFrameDefaultsKey = "NSWindow Frame com_apple_SwiftUI_Settings_window"

    private let capture: LaunchOptions.Capture
    private let model: BatteryModel
    private let logger = AppLog.logger("capture")
    private let priorSettingsFrame = UserDefaults.standard.object(forKey: settingsFrameDefaultsKey)

    init(capture: LaunchOptions.Capture, model: BatteryModel) {
        self.capture = capture
        self.model = model
    }

    func start() {
        Task {
            do {
                let window = try await presentWindow()
                try await waitForTelemetry()
                try await Task.sleep(for: Self.settleDelay)
                let data = try WindowImage.pngData(of: window, includingTitleBar: capture.target == .settings, scale: Self.outputScale)
                try write(data)
                logger.info("captured \(self.capture.outputURL.path, privacy: .public)")
                restoreSettingsFrame()
                exit(EXIT_SUCCESS)
            } catch {
                fail(error)
            }
        }
    }

    private func presentWindow() async throws -> NSWindow {
        switch capture.target {
        case .panel:
            guard let window = AppDelegate.shared?.showPanel() else { throw Failure.windowUnavailable }
            return window
        case .settings:
            model.surfaceDidAppear()
            SettingsOpener.shared.open()
            let window = try await waitForWindow { SettingsOpener.settingsWindow.flatMap { $0.isVisible ? $0 : nil } }
            window.makeKeyAndOrderFront(nil)
            return window
        }
    }

    private func waitForWindow(_ lookup: () -> NSWindow?) async throws -> NSWindow {
        let deadline = Date().addingTimeInterval(Self.windowTimeout)
        while Date() < deadline {
            if let window = lookup() { return window }
            try await Task.sleep(for: Self.pollInterval)
        }
        throw Failure.windowUnavailable
    }

    private func waitForTelemetry() async throws {
        let deadline = Date().addingTimeInterval(Self.readinessTimeout)
        while Date() < deadline {
            if missingTelemetry.isEmpty { return }
            try await Task.sleep(for: Self.pollInterval)
        }
        throw Failure.timedOut(waitingFor: missingTelemetry)
    }

    private var missingTelemetry: [String] {
        var missing: [String] = []
        if model.snapshot.isEmpty { missing.append("battery snapshot") }
        if model.stats?.cpu == nil { missing.append("system stats") }
        if model.energySample.isEmpty || model.energySample.isWarmingUp { missing.append("energy sample") }
        return missing
    }

    private func write(_ data: Data) throws {
        let url = capture.outputURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.writeFailed(url, error)
        }
    }

    // The Settings window autosaves its frame into the app's preferences, which a capture must leave as it found them.
    private func restoreSettingsFrame() {
        let defaults = UserDefaults.standard
        if let priorSettingsFrame {
            defaults.set(priorSettingsFrame, forKey: Self.settingsFrameDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.settingsFrameDefaultsKey)
        }
        defaults.synchronize()
    }

    private func fail(_ error: Error) {
        restoreSettingsFrame()
        logger.error("capture failed: \(error.localizedDescription, privacy: .public)")
        FileHandle.standardError.write(Data("watty: capture failed: \(error.localizedDescription)\n".utf8))
        exit(Self.failureExitCode)
    }
}

@MainActor
enum WindowImage {
    static func pngData(of window: NSWindow, includingTitleBar: Bool, scale: CGFloat) throws -> Data {
        guard let contentView = window.contentView else { throw CaptureController.Failure.windowUnavailable }
        let target = includingTitleBar ? (contentView.superview ?? contentView) : contentView
        target.layoutSubtreeIfNeeded()

        let bounds = target.bounds
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int((bounds.width * scale).rounded()),
                  pixelsHigh: Int((bounds.height * scale).rounded()),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ) else {
            throw CaptureController.Failure.renderFailed
        }

        bitmap.size = bounds.size
        target.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureController.Failure.renderFailed
        }
        return data
    }
}
