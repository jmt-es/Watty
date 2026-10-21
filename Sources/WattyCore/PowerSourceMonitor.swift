import AppKit
import Foundation
import IOKit.ps
import os

public final class PowerSourceMonitor {
    public enum Event: String {
        case powerSourceChanged
        case powerStateChanged
        case systemWoke
    }

    private static let logger = Logger(subsystem: "com.jmtes.watty", category: "monitor")

    private let handler: (Event) -> Void
    private var runLoopSource: CFRunLoopSource?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.handler(.powerSourceChanged)
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        } else {
            Self.logger.error("IOPSNotificationCreateRunLoopSource failed, power source changes will not be pushed")
        }

        observe(.NSProcessInfoPowerStateDidChange, center: NotificationCenter.default, event: .powerStateChanged)
        observe(NSWorkspace.didWakeNotification, center: NSWorkspace.shared.notificationCenter, event: .systemWoke)
        observe(NSWorkspace.screensDidWakeNotification, center: NSWorkspace.shared.notificationCenter, event: .systemWoke)
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, event: Event) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.handler(event)
        }
        observers.append((center, observer))
    }
}
