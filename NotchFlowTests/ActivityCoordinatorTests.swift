import XCTest
@testable import NotchFlow

@MainActor
final class ActivityCoordinatorTests: XCTestCase {
    func testActivitiesAreOrderedByProductPriority() {
        let coordinator = ActivityCoordinator()
        coordinator.upsert(IslandActivity(id: "music", kind: .music, title: "音乐"))
        coordinator.upsert(IslandActivity(id: "timer", kind: .timer, title: "计时器"))
        coordinator.upsert(IslandActivity(id: "critical", kind: .criticalSystem, title: "低电量"))

        XCTAssertEqual(coordinator.orderedActivities.map(\.id), ["critical", "timer", "music"])
        XCTAssertEqual(coordinator.state.activity?.id, "critical")
    }

    func testHUDQueuesWhileUserIsOperatingExpandedPanel() async {
        let coordinator = ActivityCoordinator()
        coordinator.toggleExpanded()
        coordinator.showTemporaryHUD(
            IslandActivity(id: "hud", kind: .systemHUD, title: "音量"),
            duration: .milliseconds(50)
        )

        XCTAssertEqual(coordinator.state.presentation, .expanded)
        coordinator.collapse()
        XCTAssertEqual(coordinator.state.presentation, .temporaryHUD)

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(coordinator.state.presentation, .silent)
    }

    func testHUDTemporarilyPreemptsAndRestoresCompactActivity() async {
        let coordinator = ActivityCoordinator()
        coordinator.upsert(IslandActivity(id: "music", kind: .music, title: "模拟活动"))

        coordinator.showTemporaryHUD(
            IslandActivity(id: "hud", kind: .systemHUD, title: "音量 50%"),
            duration: .milliseconds(50)
        )

        XCTAssertEqual(coordinator.state.presentation, .temporaryHUD)
        XCTAssertEqual(coordinator.state.activity?.id, "hud")

        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(coordinator.state.presentation, .compact)
        XCTAssertEqual(coordinator.state.activity?.id, "music")
    }

    func testFileReceivingPreemptsAndRestoresExpandedState() {
        let coordinator = ActivityCoordinator()
        coordinator.toggleExpanded()
        coordinator.beginFileReceiving()
        XCTAssertEqual(coordinator.state.presentation, .fileReceiving)

        coordinator.endFileReceiving()
        XCTAssertEqual(coordinator.state.presentation, .expanded)
    }

    func testRemovingHighestActivityRestoresNextActivity() {
        let coordinator = ActivityCoordinator()
        coordinator.upsert(IslandActivity(id: "music", kind: .music, title: "音乐"))
        coordinator.upsert(IslandActivity(id: "timer", kind: .timer, title: "计时器"))
        XCTAssertEqual(coordinator.state.activity?.id, "timer")

        coordinator.removeActivity(id: "timer")
        XCTAssertEqual(coordinator.state.activity?.id, "music")
    }

    func testHoverIgnoresResizeExitUntilPointerIsReallyOutside() async {
        let coordinator = ActivityCoordinator()
        coordinator.pointerEntered()
        try? await Task.sleep(for: .milliseconds(230))
        XCTAssertEqual(coordinator.state.presentation, .hoverPreview)

        coordinator.pointerExited(isPointerOutside: { false })
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(coordinator.state.presentation, .hoverPreview)

        coordinator.pointerExited(isPointerOutside: { true })
        try? await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(coordinator.state.presentation, .silent)
    }
}
