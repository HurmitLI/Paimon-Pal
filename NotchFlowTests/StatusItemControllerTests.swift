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
        controller.onOpenSettings = { didOpenSettings = true }
        controller.onToggleIsland = { didToggleIsland = true }

        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)

        XCTAssertNotNil(menu.item(withTitle: "暂停 1 小时"))
        XCTAssertNotNil(menu.item(withTitle: "暂停至明天"))
        send(menu.item(withTitle: "打开设置…"))
        send(menu.item(withTitle: "展开刘海"))
        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(didToggleIsland)
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
