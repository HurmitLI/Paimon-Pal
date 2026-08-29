import AppKit
import XCTest
@testable import NotchFlow

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testRunningMenuExposesActionsAndDispatchesToggle() {
        let (preferences, suiteName) = makePreferences()
        let controller = StatusItemController(preferences: preferences)
        defer {
            controller.setVisible(false)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        var didOpenSettings = false
        var didToggleIsland = false
        var didToggleContinuousVoice = false
        var didToggleListening = false
        var didToggleSpeaking = false
        var didTestSuccess = false
        controller.onOpenSettings = { didOpenSettings = true }
        controller.onToggleIsland = { didToggleIsland = true }
        controller.onToggleContinuousVoice = { didToggleContinuousVoice = true }
#if DEBUG
        controller.onTogglePetListening = { didToggleListening = true }
        controller.onTogglePetSpeaking = { didToggleSpeaking = true }
        controller.onTestPetSuccess = { didTestSuccess = true }
#endif

        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)

        XCTAssertNotNil(menu.item(withTitle: "暂停 1 小时"))
        XCTAssertNotNil(menu.item(withTitle: "暂停至明天"))
        send(menu.item(withTitle: "打开设置…"))
        send(menu.item(withTitle: "展开刘海"))
        send(menu.item(withTitle: "开启 AI 对话实验模式"))
#if DEBUG
        send(menu.item(withTitle: "测试派蒙聆听"))
        send(menu.item(withTitle: "测试派蒙说话"))
        send(menu.item(withTitle: "测试派蒙成功反馈"))
#endif
        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(didToggleIsland)
        XCTAssertTrue(didToggleContinuousVoice)
#if DEBUG
        XCTAssertTrue(didToggleListening)
        XCTAssertTrue(didToggleSpeaking)
        XCTAssertTrue(didTestSuccess)
#endif
    }

    func testContinuousVoiceMenuShowsLivePhaseAndStopAction() {
        let (preferences, suiteName) = makePreferences()
        let controller = StatusItemController(preferences: preferences)
        defer {
            controller.setVisible(false)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        controller.continuousVoicePhase = { .listening }

        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)

        XCTAssertNotNil(menu.item(withTitle: "停止 AI 对话实验模式"))
        XCTAssertNotNil(menu.item(withTitle: "语音状态：正在听"))
    }

    func testPausedMenuKeepsRecoveryAndDisablesIslandToggle() {
        let (preferences, suiteName) = makePreferences()
        preferences.pauseForOneHour()
        let controller = StatusItemController(preferences: preferences)
        defer {
            controller.setVisible(false)
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        var didResume = false
        controller.onResume = { didResume = true }

        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)

        XCTAssertNil(menu.item(withTitle: "暂停 1 小时"))
        XCTAssertFalse(menu.item(withTitle: "展开刘海")?.isEnabled ?? true)
        send(menu.item(withTitle: "立即恢复"))
        XCTAssertTrue(didResume)
    }

    private func makePreferences() -> (AppPreferences, String) {
        let suiteName = "NotchFlowTests.StatusItem.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (AppPreferences(defaults: defaults), suiteName)
    }

    private func send(_ item: NSMenuItem?) {
        guard let item, let action = item.action else {
            XCTFail("Expected actionable menu item")
            return
        }
        XCTAssertTrue(NSApp.sendAction(action, to: item.target, from: item))
    }
}
