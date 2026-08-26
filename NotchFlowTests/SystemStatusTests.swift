import XCTest
@testable import NotchFlow

@MainActor
final class SystemStatusTests: XCTestCase {
    func testInvalidSystemValuesAreRejected() {
        XCTAssertNil(BatteryStatusSnapshot(level: -0.1, isCharging: false, connection: .batteryPower).level)
        XCTAssertNil(BatteryStatusSnapshot(level: 1.1, isCharging: false, connection: .batteryPower).level)
        XCTAssertNil(AudioStatusSnapshot(volume: .infinity, isMuted: false).volume)
        XCTAssertNil(AudioStatusSnapshot(volume: 2, isMuted: false).volume)
    }

    func testInitialAudioSnapshotDoesNotShowHUD() {
        let current = AudioStatusSnapshot(volume: 0.5, isMuted: false)
        XCTAssertTrue(SystemStatusEventResolver.audioEvents(previous: nil, current: current).isEmpty)
    }

    func testPowerTransitionsAndLowBatteryAreResolved() {
        let charging = BatteryStatusSnapshot(level: 0.3, isCharging: true, connection: .acPower)
        let battery = BatteryStatusSnapshot(level: 0.3, isCharging: false, connection: .batteryPower)
        let low = BatteryStatusSnapshot(level: 0.2, isCharging: false, connection: .batteryPower)

        XCTAssertEqual(
            SystemStatusEventResolver.powerEvents(previous: battery, current: charging),
            [.powerConnected(charging)]
        )
        XCTAssertEqual(
            SystemStatusEventResolver.powerEvents(previous: charging, current: battery),
            [.powerDisconnected(battery)]
        )
        XCTAssertEqual(
            SystemStatusEventResolver.powerEvents(previous: battery, current: low),
            [.lowBattery(low)]
        )
    }

    func testContinuousVolumeChangesReuseOneHUDAndRefreshItsValue() {
        let coordinator = ActivityCoordinator()
        let first = SystemStatusEvent.volumeChanged(AudioStatusSnapshot(volume: 0.4, isMuted: false))
        let second = SystemStatusEvent.volumeChanged(AudioStatusSnapshot(volume: 0.5, isMuted: false))

        coordinator.showTemporaryHUD(first.activity, duration: .seconds(1))
        coordinator.showTemporaryHUD(second.activity, duration: .seconds(1))

        XCTAssertEqual(coordinator.state.presentation, .temporaryHUD)
        XCTAssertEqual(coordinator.state.activity?.id, "system.audio")
        XCTAssertEqual(coordinator.state.activity?.title, "音量 50%")
        XCTAssertEqual(coordinator.state.activity?.progress, 0.5)
    }

    func testLowBatteryPreemptsExpandedButOrdinaryVolumeWaits() {
        let coordinator = ActivityCoordinator()
        coordinator.showExpanded()
        coordinator.showTemporaryHUD(
            SystemStatusEvent.volumeChanged(AudioStatusSnapshot(volume: 0.5, isMuted: false)).activity
        )
        XCTAssertEqual(coordinator.state.presentation, .expanded)

        let low = BatteryStatusSnapshot(level: 0.1, isCharging: false, connection: .batteryPower)
        coordinator.showTemporaryHUD(SystemStatusEvent.lowBattery(low).activity)
        XCTAssertEqual(coordinator.state.presentation, .temporaryHUD)
        XCTAssertEqual(coordinator.state.activity?.kind, .criticalSystem)
    }

    func testCurrentMacProvidesBatteryAndAudioThroughPublicInterfaces() {
        let reader = LiveSystemStatusReader()
        XCTAssertNotNil(reader.readBattery())
        XCTAssertNotNil(reader.readAudio())
    }
}
