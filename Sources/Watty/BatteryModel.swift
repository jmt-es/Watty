import AppKit
import Foundation
import os
import WattyCore

enum RefreshCadence {
    static let visibleSnapshot: TimeInterval = 2
    static let hiddenSnapshot: TimeInterval = 30
    static let visibleEnergy: TimeInterval = 5
    static let hiddenEnergy: TimeInterval = 60
    static let clockTick: TimeInterval = 1
    static let staleAfter: TimeInterval = 45
    static let powerEventCoalesce: TimeInterval = 0.4
    static let manualSpinnerMinimum: TimeInterval = 0.6
    static let statsWindow: TimeInterval = 600
    static let statsMinimumWindow: TimeInterval = 20
    static let statsLimit = 400
    static let statsWarmup: TimeInterval = 1
    static let statusLifetime: TimeInterval = 8
}

enum RefreshTrigger: String {
    case launch
    case timer
    case surface
    case powerEvent
    case manual
    case modeChange
    case queued
}

enum Freshness: Equatable {
    case waiting
    case live
    case refreshing
    case stale
}

@MainActor
final class BatteryModel: ObservableObject {
    @Published private(set) var snapshot: BatterySnapshot = .empty
    @Published private(set) var energySample: EnergySample = .empty
    @Published private(set) var historySamples: [BatteryHistorySample] = []
    @Published private(set) var drainPeriods: [DateInterval] = []
    @Published private(set) var historyWarning: String?
    @Published private(set) var stats: SystemStats?
    @Published private(set) var statsHistory: [SystemStats] = []
    @Published private(set) var isRefreshingSnapshot = false
    @Published private(set) var showsManualSpinner = false
    @Published private(set) var isSamplingEnergy = false
    @Published private(set) var actionStatus: ServiceActionResult?
    @Published private(set) var applyingPowerMode: PowerMode?
    @Published private(set) var lastTrigger: RefreshTrigger?
    @Published private(set) var now = Date()
    @Published var selectedPowerMode: PowerMode = .automatic {
        didSet { selectionChanged(from: oldValue) }
    }

    private let service: TelemetryProviding
    private let historyStore: BatteryHistoryStore
    private let alertCoordinator: BatteryAlertCoordinator?
    private let logger = AppLog.logger("model")
    private var netFlowEstimator = NetFlowEstimator()
    private var monitor: PowerSourceMonitor?
    private var sleepObserver: NSObjectProtocol?
    private var visibleSurfaces = 0
    private var snapshotTask: Task<Void, Never>?
    private var energyTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var cadenceTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var queuedSnapshotTrigger: RefreshTrigger?
    private var lastPowerEventAt = Date.distantPast
    private var isSyncingSelection = false

    init(
        service: TelemetryProviding = BatteryService.shared,
        historyStore: BatteryHistoryStore = BatteryHistoryStore(),
        alertCoordinator: BatteryAlertCoordinator? = nil,
        seededStatsHistory: [SystemStats] = [],
        seededNetFlowReadings: [NetFlowReading] = [],
        observesPowerEvents: Bool = true
    ) {
        self.service = service
        self.historyStore = historyStore
        self.alertCoordinator = alertCoordinator

        historyStore.load()
        historySamples = historyStore.history.samples
        drainPeriods = PluggedInDrainPeriods.detect(in: historySamples)
        if seededNetFlowReadings.isEmpty {
            netFlowEstimator.seed(with: historySamples)
        } else {
            netFlowEstimator.seed(withReadings: seededNetFlowReadings)
        }
        statsHistory = seededStatsHistory

        if observesPowerEvents {
            startObservingPowerEvents()
        }

        refreshSnapshot(trigger: .launch)
        refreshEnergy(trigger: .launch)
        refreshStats()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(RefreshCadence.statsWarmup))
            self?.refreshStats()
        }
        restartCadence()
    }

    private func startObservingPowerEvents() {
        let monitor = PowerSourceMonitor { [weak self] event in
            Task { @MainActor in
                self?.powerEventOccurred(event)
            }
        }
        monitor.start()
        self.monitor = monitor
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistHistory()
            }
        }
    }

    deinit {
        cadenceTask?.cancel()
        clockTask?.cancel()
        statusTask?.cancel()
        snapshotTask?.cancel()
        energyTask?.cancel()
        statsTask?.cancel()
        monitor?.stop()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }

    var isVisible: Bool {
        visibleSurfaces > 0
    }

    var freshness: Freshness {
        if snapshot.isEmpty { return .waiting }
        if showsManualSpinner { return .refreshing }
        return now.timeIntervalSince(snapshot.lastUpdated) > RefreshCadence.staleAfter ? .stale : .live
    }

    var availablePowerModes: [PowerMode] {
        snapshot.powerModeSupport.availableModes
    }

    var hasBattery: Bool {
        snapshot.hasBattery
    }

    var versionText: String {
        "v\(WattyVersion.current) (\(WattyVersion.build))"
    }

    func surfaceDidAppear() {
        visibleSurfaces += 1
        logger.debug("surface appeared visible=\(self.visibleSurfaces)")
        if visibleSurfaces == 1 {
            restartCadence()
            startClock()
        }
        refreshSnapshot(trigger: .surface)
        refreshStats()
        if now.timeIntervalSince(energySample.sampledAt) > RefreshCadence.visibleEnergy / 2 {
            refreshEnergy(trigger: .surface)
        }
    }

    func surfaceDidDisappear() {
        visibleSurfaces = max(0, visibleSurfaces - 1)
        logger.debug("surface disappeared visible=\(self.visibleSurfaces)")
        if visibleSurfaces == 0 {
            restartCadence()
            stopClock()
        }
    }

    func refreshNow() {
        showsManualSpinner = true
        refreshSnapshot(trigger: .manual)
        refreshEnergy(trigger: .manual)
        refreshStats()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(RefreshCadence.manualSpinnerMinimum))
            guard let self else { return }
            while self.isRefreshingSnapshot {
                try? await Task.sleep(for: .milliseconds(50))
            }
            self.showsManualSpinner = false
        }
    }

    func openBatterySettings() {
        service.openBatterySettings()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func persistHistory() {
        historyStore.save()
        updateHistoryWarning()
    }

    private func powerEventOccurred(_ event: PowerSourceMonitor.Event) {
        let elapsed = Date().timeIntervalSince(lastPowerEventAt)
        guard elapsed > RefreshCadence.powerEventCoalesce else { return }
        lastPowerEventAt = Date()
        logger.info("power event \(event.rawValue, privacy: .public)")
        refreshSnapshot(trigger: .powerEvent)
    }

    private func refreshSnapshot(trigger: RefreshTrigger) {
        if snapshotTask != nil {
            queuedSnapshotTrigger = trigger
            return
        }

        isRefreshingSnapshot = true
        lastTrigger = trigger
        let forceDetails = trigger == .launch || trigger == .manual || trigger == .modeChange
        let depth = snapshotDepth(for: trigger)
        logger.debug("snapshot requested trigger=\(trigger.rawValue, privacy: .public) depth=\(String(describing: depth), privacy: .public)")

        snapshotTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.service.fetchSnapshot(depth: depth, forceDetails: forceDetails)
            self.receive(snapshot, trigger: trigger, depth: depth)
            self.snapshotTask = nil
            self.isRefreshingSnapshot = false
            if let queued = self.queuedSnapshotTrigger {
                self.queuedSnapshotTrigger = nil
                self.refreshSnapshot(trigger: queued)
            }
        }
    }

    // The Power (W) menu bar display needs the ioreg read that essentials skip.
    private func snapshotDepth(for trigger: RefreshTrigger) -> SnapshotDepth {
        guard trigger == .timer, !isVisible else { return .full }
        return snapshot.hasBattery && Preferences.menuBarDisplay() == .power ? .full : .essentials
    }

    private func receive(_ received: BatterySnapshot, trigger: RefreshTrigger, depth: SnapshotDepth) {
        let previous = self.snapshot
        var snapshot = depth == .essentials ? received.fillingMissingDetails(from: previous) : received
        snapshot.netFlow = netFlowEstimator.record(snapshot)
        self.snapshot = snapshot
        now = Date()
        recordHistory(of: snapshot)
        alertCoordinator?.snapshotDidUpdate(snapshot)

        if applyingPowerMode == nil, depth == .full {
            syncSelection(to: snapshot.powerMode ?? .automatic)
        }

        if previous.chargeState != snapshot.chargeState {
            logger.info("charge state \(previous.chargeState.title, privacy: .public) -> \(snapshot.chargeState.title, privacy: .public) (\(trigger.rawValue, privacy: .public))")
        }
        if previous.netFlow.flow != snapshot.netFlow.flow {
            logger.info("net flow \(previous.netFlow.flow?.rawValue ?? "unknown", privacy: .public) -> \(snapshot.netFlow.flow?.rawValue ?? "unknown", privacy: .public) average=\(snapshot.netFlow.averageBatteryWatts ?? .nan, format: .fixed(precision: 1)) W trend=\(snapshot.netFlow.levelTrendPointsPerMinute ?? .nan, format: .fixed(precision: 2)) pt/min")
        }
    }

    private func refreshEnergy(trigger: RefreshTrigger) {
        guard energyTask == nil else { return }

        isSamplingEnergy = true
        energyTask = Task { [weak self] in
            guard let self else { return }
            let sample = await self.service.fetchEnergySample()
            self.energySample = sample
            self.now = Date()
            self.energyTask = nil
            self.isSamplingEnergy = false
        }
    }

    private func refreshStats() {
        guard statsTask == nil else { return }
        statsTask = Task { [weak self] in
            guard let self else { return }
            let sample = await self.service.fetchSystemStats()
            self.stats = sample
            self.appendStats(sample)
            self.statsTask = nil
        }
    }

    private func appendStats(_ sample: SystemStats) {
        statsHistory.append(sample)
        let cutoff = sample.date.addingTimeInterval(-RefreshCadence.statsWindow)
        statsHistory.removeAll { $0.date < cutoff }
        if statsHistory.count > RefreshCadence.statsLimit {
            statsHistory.removeFirst(statsHistory.count - RefreshCadence.statsLimit)
        }
    }

    private func selectionChanged(from previous: PowerMode) {
        guard !isSyncingSelection, previous != selectedPowerMode, applyingPowerMode == nil else { return }
        applyPowerMode(selectedPowerMode, revertingTo: previous)
    }

    private func applyPowerMode(_ mode: PowerMode, revertingTo previous: PowerMode) {
        applyingPowerMode = mode
        actionStatus = nil
        logger.info("user requested power mode \(mode.title, privacy: .public)")

        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.setPowerMode(mode)
            self.applyingPowerMode = nil
            self.showStatus(result)
            if !result.success {
                self.syncSelection(to: result.resultingMode ?? previous)
            }
            self.refreshSnapshot(trigger: .modeChange)
        }
    }

    private func syncSelection(to mode: PowerMode) {
        guard selectedPowerMode != mode else { return }
        isSyncingSelection = true
        selectedPowerMode = mode
        isSyncingSelection = false
    }

    private func showStatus(_ result: ServiceActionResult) {
        actionStatus = result
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(RefreshCadence.statusLifetime))
            guard !Task.isCancelled else { return }
            self?.actionStatus = nil
        }
    }

    private func restartCadence() {
        cadenceTask?.cancel()
        let snapshotInterval = isVisible ? RefreshCadence.visibleSnapshot : RefreshCadence.hiddenSnapshot
        let energyInterval = isVisible ? RefreshCadence.visibleEnergy : RefreshCadence.hiddenEnergy
        logger.debug("cadence snapshot=\(snapshotInterval)s energy=\(energyInterval)s")

        cadenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(snapshotInterval))
                guard !Task.isCancelled, let self else { return }
                self.refreshSnapshot(trigger: .timer)
                self.refreshStats()
                if Date().timeIntervalSince(self.energySample.sampledAt) >= energyInterval {
                    self.refreshEnergy(trigger: .timer)
                }
            }
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RefreshCadence.clockTick))
                guard !Task.isCancelled else { return }
                self?.now = Date()
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func recordHistory(of snapshot: BatterySnapshot) {
        guard snapshot.hasBattery, !snapshot.isEmpty else { return }
        let recorded = historyStore.record(
            level: snapshot.level,
            isCharging: snapshot.isCharging,
            onAdapter: snapshot.powerSource == .adapter,
            at: snapshot.lastUpdated
        )
        if recorded {
            historySamples = historyStore.history.samples
            drainPeriods = PluggedInDrainPeriods.detect(in: historySamples)
        }
        historyStore.saveIfDue()
        updateHistoryWarning()
    }

    private func updateHistoryWarning() {
        let warning = historyStore.isSaveFailing ? String(localized: "Battery history can't be saved") : nil
        if warning != historyWarning {
            historyWarning = warning
        }
    }
}
