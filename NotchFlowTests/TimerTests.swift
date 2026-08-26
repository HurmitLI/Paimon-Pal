import XCTest
@testable import NotchFlow

final class TimerEngineTests: XCTestCase {
    private let startDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testRunningTimerUsesTargetDateAndCorrectsAfterLongGap() {
        var state = TimerRuntimeState.idle
        XCTAssertTrue(state.begin(seconds: 120, now: startDate))

        XCTAssertEqual(state.remainingSeconds(at: startDate.addingTimeInterval(90)), 30)
        XCTAssertEqual(state.remainingSeconds(at: startDate.addingTimeInterval(119.2)), 1)
        XCTAssertEqual(state.refresh(now: startDate.addingTimeInterval(120)), .finished)
        XCTAssertEqual(state.phase, .ringing)
    }

    func testPauseAndResumeKeepExactRemainingDuration() {
        var state = TimerRuntimeState.idle
        XCTAssertTrue(state.begin(seconds: 100, now: startDate))
        XCTAssertTrue(state.pause(now: startDate.addingTimeInterval(30)))
        XCTAssertEqual(state.remainingSeconds(at: startDate.addingTimeInterval(500)), 70)

        XCTAssertTrue(state.resume(now: startDate.addingTimeInterval(500)))
        XCTAssertEqual(state.remainingSeconds(at: startDate.addingTimeInterval(550)), 20)
    }

    func testRestoreRecoversFutureTimerAndDropsLongExpiredTimer() {
        var future = TimerRuntimeState.idle
        XCTAssertTrue(future.begin(seconds: 120, now: startDate))
        XCTAssertEqual(future.reconcileAfterRestore(now: startDate.addingTimeInterval(60)), .none)
        XCTAssertEqual(future.remainingSeconds(at: startDate.addingTimeInterval(60)), 60)

        var expired = TimerRuntimeState.idle
        XCTAssertTrue(expired.begin(seconds: 10, now: startDate))
        XCTAssertEqual(expired.reconcileAfterRestore(now: startDate.addingTimeInterval(50)), .autoDismissed)
        XCTAssertEqual(expired, .idle)
    }

    func testRecentExpiredTimerRestoresRingingForRemainingWindow() {
        var state = TimerRuntimeState.idle
        XCTAssertTrue(state.begin(seconds: 10, now: startDate))

        XCTAssertEqual(state.reconcileAfterRestore(now: startDate.addingTimeInterval(20)), .finished)
        XCTAssertEqual(state.phase, .ringing)
        XCTAssertEqual(state.ringingStartedAt, startDate.addingTimeInterval(10))
        XCTAssertEqual(state.refresh(now: startDate.addingTimeInterval(40)), .autoDismissed)
        XCTAssertEqual(state, .idle)
    }

    func testTimerTextFormatting() {
        XCTAssertEqual(TimerTextFormatter.clock(seconds: 5), "00:05")
        XCTAssertEqual(TimerTextFormatter.clock(seconds: 65), "01:05")
        XCTAssertEqual(TimerTextFormatter.clock(seconds: 3661), "01:01:01")
        XCTAssertEqual(TimerTextFormatter.duration(seconds: 90), "1 分 30 秒")
    }

    func testUserDefaultsStoreRoundTripsTimerState() {
        let suiteName = "NotchFlowTests.Timer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsTimerStore(defaults: defaults, key: "timer")
        var state = TimerRuntimeState.idle
        XCTAssertTrue(state.begin(seconds: 300, now: startDate))

        store.save(state)
        XCTAssertEqual(store.load(), state)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testCorruptTimerPayloadIsClearedInsteadOfRestored() {
        let suiteName = "NotchFlowTests.Timer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsTimerStore(defaults: defaults, key: "timer")
        defaults.set(Data("not-json".utf8), forKey: "timer")

        XCTAssertNil(store.load())
        XCTAssertNil(defaults.object(forKey: "timer"))
    }

    func testSemanticallyInvalidTimerStateIsCleared() throws {
        let suiteName = "NotchFlowTests.Timer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsTimerStore(defaults: defaults, key: "timer")
        let invalid = TimerRuntimeState(
            phase: .running,
            totalSeconds: 300,
            endDate: nil,
            pausedRemainingSeconds: nil,
            ringingStartedAt: nil
        )
        defaults.set(try JSONEncoder().encode(invalid), forKey: "timer")

        XCTAssertNil(store.load())
        XCTAssertNil(defaults.object(forKey: "timer"))
    }
}

@MainActor
final class TimerControllerTests: XCTestCase {
    func testStartingAndPausingTimerSynchronizesCoordinatorActivity() {
        let coordinator = ActivityCoordinator()
        let store = MemoryTimerStore()
        let timer = TimerController(coordinator: coordinator, store: store)
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)

        timer.begin(seconds: 90, now: now)
        XCTAssertEqual(coordinator.state.activity?.kind, .timer)
        XCTAssertEqual(coordinator.state.activity?.title, "01:30")
        XCTAssertEqual(coordinator.state.activity?.progress, 1)

        timer.pause(now: now.addingTimeInterval(30))
        XCTAssertEqual(coordinator.state.activity?.detail, "已暂停")
        XCTAssertEqual(coordinator.state.activity?.title, "01:00")

        coordinator.showExpanded()
        XCTAssertEqual(coordinator.state.presentation, .expanded)
        timer.cancel()
        XCTAssertEqual(coordinator.state.presentation, .silent)
        XCTAssertNil(store.state)
    }

    func testStoppingControllerRemovesActivityButPreservesTimerState() {
        let coordinator = ActivityCoordinator()
        let store = MemoryTimerStore()
        let timer = TimerController(coordinator: coordinator, store: store)
        let now = Date()

        timer.begin(seconds: 120, now: now)
        XCTAssertEqual(coordinator.state.activity?.id, "timer.active")
        XCTAssertNotNil(store.state)

        timer.stop()

        XCTAssertNil(coordinator.state.activity)
        XCTAssertNotNil(store.state)
        XCTAssertEqual(timer.state.phase, .running)
        XCTAssertTrue(timer.message.contains("保留"))
    }

    func testNewControllerRestoresPersistedRunningTimer() {
        let now = Date()
        var persisted = TimerRuntimeState.idle
        XCTAssertTrue(persisted.begin(seconds: 120, now: now))
        let store = MemoryTimerStore()
        store.state = persisted
        let coordinator = ActivityCoordinator()
        let restored = TimerController(coordinator: coordinator, store: store)

        restored.start()
        defer { restored.stop() }

        XCTAssertEqual(restored.state.phase, .running)
        XCTAssertGreaterThan(restored.remainingSeconds, 0)
        XCTAssertEqual(coordinator.state.activity?.id, "timer.active")
    }
}

private final class MemoryTimerStore: TimerStateStoring {
    var state: TimerRuntimeState?

    func load() -> TimerRuntimeState? { state }
    func save(_ state: TimerRuntimeState) { self.state = state }
    func clear() { state = nil }
}
