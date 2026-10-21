import XCTest
@testable import WattyCore

final class BatteryHistoryStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watty-history-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL {
        directory.appendingPathComponent(BatteryHistoryStore.fileName)
    }

    private var corruptURL: URL {
        directory.appendingPathComponent(BatteryHistoryStore.corruptFileName)
    }

    private func makeStore(writesEnabled: Bool = true) -> BatteryHistoryStore {
        BatteryHistoryStore(fileURL: fileURL, writesEnabled: writesEnabled)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testIgnoresUnchangedSamplesWithinAMinute() {
        var history = BatteryHistory()

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: false)))
        XCTAssertFalse(history.record(BatteryHistorySample(date: at(30), level: 80, isCharging: false, onAdapter: false)))
        XCTAssertFalse(history.record(BatteryHistorySample(date: at(59), level: 80, isCharging: false, onAdapter: false)))

        XCTAssertEqual(history.samples.count, 1)
    }

    func testRecordsUnchangedSampleOnceAMinuteHasPassed() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: false))

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(60), level: 80, isCharging: false, onAdapter: false)))

        XCTAssertEqual(history.samples.map(\.date), [at(0), at(60)])
    }

    func testRecordsImmediatelyWhenLevelChanges() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: false))

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(5), level: 79, isCharging: false, onAdapter: false)))
    }

    func testRecordsImmediatelyWhenChargingStateChanges() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: true))

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(5), level: 80, isCharging: true, onAdapter: true)))
    }

    func testRecordsImmediatelyWhenAdapterStateChanges() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: true))

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(5), level: 80, isCharging: false, onAdapter: false)))
    }

    func testIgnoresSampleWithTheSameDate() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: false))

        XCTAssertFalse(history.record(BatteryHistorySample(date: at(0), level: 70, isCharging: true, onAdapter: true)))
        XCTAssertEqual(history.samples.count, 1)
    }

    func testClampsLevelToValidRange() {
        XCTAssertEqual(BatteryHistorySample(date: at(0), level: 140, isCharging: true, onAdapter: true).level, 100)
        XCTAssertEqual(BatteryHistorySample(date: at(0), level: -3, isCharging: false, onAdapter: false).level, 0)
    }

    func testKeepsOnlyTwentyFourHours() {
        var history = BatteryHistory()
        let hour: TimeInterval = 3_600
        for index in 0...26 {
            history.record(BatteryHistorySample(date: at(Double(index) * hour), level: 90 - index, isCharging: false, onAdapter: false))
        }

        let newest = at(26 * hour)
        XCTAssertEqual(history.samples.last?.date, newest)
        XCTAssertGreaterThanOrEqual(history.samples.first?.date ?? .distantPast, newest.addingTimeInterval(-BatteryHistory.retention))
        XCTAssertEqual(history.samples.count, 25)
    }

    func testCapsTheNumberOfSamples() {
        var history = BatteryHistory()
        for index in 0..<(BatteryHistory.maximumSamples + 50) {
            history.record(BatteryHistorySample(date: at(Double(index)), level: index % 2 == 0 ? 50 : 51, isCharging: false, onAdapter: false))
        }

        XCTAssertEqual(history.samples.count, BatteryHistory.maximumSamples)
        XCTAssertEqual(history.samples.last?.date, at(Double(BatteryHistory.maximumSamples + 49)))
    }

    func testClockMovingBackwardsDropsSamplesFromTheFuture() {
        var history = BatteryHistory()
        history.record(BatteryHistorySample(date: at(0), level: 80, isCharging: false, onAdapter: false))
        history.record(BatteryHistorySample(date: at(600), level: 78, isCharging: false, onAdapter: false))
        history.record(BatteryHistorySample(date: at(1_200), level: 76, isCharging: false, onAdapter: false))

        XCTAssertTrue(history.record(BatteryHistorySample(date: at(700), level: 77, isCharging: false, onAdapter: false)))

        XCTAssertEqual(history.samples.map(\.date), [at(0), at(600), at(700)])
    }

    func testSamplesSinceReturnsTheRequestedWindow() {
        var history = BatteryHistory()
        for index in 0..<5 {
            history.record(BatteryHistorySample(date: at(Double(index) * 600), level: 80 - index, isCharging: false, onAdapter: false))
        }

        XCTAssertEqual(history.samples(since: at(1_200)).map(\.level), [78, 77, 76])
    }

    func testMissingFileStartsEmpty() {
        let store = makeStore()

        store.load(now: at(0))

        XCTAssertTrue(store.history.samples.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(10))
        store.record(level: 81, isCharging: true, onAdapter: true, at: at(100))
        store.save(now: at(100))

        let reloaded = makeStore()
        reloaded.load(now: at(200))

        XCTAssertEqual(reloaded.history.samples, store.history.samples)
        XCTAssertEqual(reloaded.history.samples.last?.isCharging, true)
        XCTAssertEqual(reloaded.history.samples.last?.onAdapter, true)
    }

    func testSaveCreatesMissingDirectoryAndLeavesOnlyTheFinalFile() throws {
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 50, isCharging: false, onAdapter: false, at: at(10))

        store.save(now: at(10))

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(contents, [BatteryHistoryStore.fileName])
        XCTAssertFalse(store.isSaveFailing)
    }

    func testSaveIfDueWaitsForTheSaveInterval() {
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(10))

        store.saveIfDue(now: at(BatteryHistoryStore.saveInterval - 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        store.saveIfDue(now: at(BatteryHistoryStore.saveInterval))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSaveIfDueRestartsTheIntervalAfterEachWrite() throws {
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(10))
        store.saveIfDue(now: at(BatteryHistoryStore.saveInterval))
        let firstWrite = try Data(contentsOf: fileURL)

        store.record(level: 79, isCharging: false, onAdapter: false, at: at(BatteryHistoryStore.saveInterval + 10))
        store.saveIfDue(now: at(BatteryHistoryStore.saveInterval + 20))

        XCTAssertEqual(try Data(contentsOf: fileURL), firstWrite)
    }

    func testSaveIfDueSkipsWhenNothingChanged() {
        let store = makeStore()
        store.load(now: at(0))

        store.saveIfDue(now: at(BatteryHistoryStore.saveInterval * 3))

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testSaveOnQuitIgnoresTheInterval() {
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(10))

        store.save(now: at(11))

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testLoadDropsExpiredAndFutureSamples() throws {
        let store = makeStore()
        store.load(now: at(0))
        let now = at(10 * 3_600)
        store.record(level: 90, isCharging: false, onAdapter: false, at: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(5 * 3_600))
        store.record(level: 70, isCharging: false, onAdapter: false, at: now)
        store.save(now: now)

        let reloaded = makeStore()
        reloaded.load(now: at(30 * 3_600))
        XCTAssertEqual(reloaded.history.samples.map(\.level), [70])

        let earlier = makeStore()
        earlier.load(now: at(5 * 3_600 + 10))
        XCTAssertEqual(earlier.history.samples.map(\.level), [90, 80])
    }

    func testLoadSortsAndDeduplicatesSamples() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"version":1,"samples":[
        {"date":"2027-01-15T08:02:00Z","level":70,"isCharging":false,"onAdapter":false},
        {"date":"2027-01-15T08:00:00Z","level":72,"isCharging":false,"onAdapter":false},
        {"date":"2027-01-15T08:00:00Z","level":72,"isCharging":false,"onAdapter":false},
        {"date":"2027-01-15T08:01:00Z","level":250,"isCharging":false,"onAdapter":false}
        ]}
        """
        try Data(json.utf8).write(to: fileURL)
        let store = makeStore()

        store.load(now: ISO8601DateFormatter().date(from: "2027-01-15T09:00:00Z")!)

        XCTAssertEqual(store.history.samples.map(\.level), [72, 100, 70])
    }

    func testCorruptFileIsSetAsideAndReplaced() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ this is not json".utf8).write(to: fileURL)
        let store = makeStore()

        store.load(now: at(0))

        XCTAssertTrue(store.history.samples.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try String(contentsOf: corruptURL), "{ this is not json")

        store.record(level: 60, isCharging: false, onAdapter: false, at: at(10))
        store.save(now: at(10))

        let reloaded = makeStore()
        reloaded.load(now: at(20))
        XCTAssertEqual(reloaded.history.samples.map(\.level), [60])
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))
    }

    func testEmptyFileIsTreatedAsCorrupt() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: fileURL)
        let store = makeStore()

        store.load(now: at(0))

        XCTAssertTrue(store.history.samples.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptURL.path))
    }

    func testNewerFileVersionIsSetAsideInsteadOfOverwritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"version":99,"samples":[]}"#.utf8).write(to: fileURL)
        let store = makeStore()

        store.load(now: at(0))

        XCTAssertTrue(store.history.samples.isEmpty)
        XCTAssertEqual(try String(contentsOf: corruptURL), #"{"version":99,"samples":[]}"#)
    }

    func testSecondCorruptionReplacesThePreviousSetAsideCopy() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: corruptURL)
        try Data("second".utf8).write(to: fileURL)

        makeStore().load(now: at(0))

        XCTAssertEqual(try String(contentsOf: corruptURL), "second")
    }

    func testReadOnlyStoreLoadsButNeverWrites() throws {
        let writer = makeStore()
        writer.load(now: at(0))
        writer.record(level: 55, isCharging: false, onAdapter: false, at: at(10))
        writer.save(now: at(10))
        let before = try Data(contentsOf: fileURL)

        let readOnly = makeStore(writesEnabled: false)
        readOnly.load(now: at(20))
        readOnly.record(level: 54, isCharging: false, onAdapter: false, at: at(30))
        readOnly.save(now: at(30))
        readOnly.saveIfDue(now: at(30 + BatteryHistoryStore.saveInterval))

        XCTAssertEqual(readOnly.history.samples.map(\.level), [55, 54])
        XCTAssertEqual(try Data(contentsOf: fileURL), before)
    }

    func testReadOnlyStoreLeavesAnUnreadableFileInPlace() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: fileURL)

        makeStore(writesEnabled: false).load(now: at(0))

        XCTAssertEqual(try String(contentsOf: fileURL), "garbage")
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
    }

    func testFailedSaveIsReportedAndRetriedAfterTheInterval() throws {
        try Data("not a directory".utf8).write(to: directory)
        let store = makeStore()
        store.load(now: at(0))
        store.record(level: 80, isCharging: false, onAdapter: false, at: at(10))

        store.save(now: at(10))

        XCTAssertTrue(store.isSaveFailing)

        try FileManager.default.removeItem(at: directory)
        store.saveIfDue(now: at(10 + BatteryHistoryStore.saveInterval))

        XCTAssertFalse(store.isSaveFailing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDefaultFileLivesInApplicationSupport() {
        let url = BatteryHistoryStore.defaultFileURL

        XCTAssertEqual(url.lastPathComponent, "battery-history.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Watty")
        XCTAssertTrue(url.path.contains("/Library/Application Support/"))
    }
}
