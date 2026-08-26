import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onToggleIsland: (() -> Void)?
    var onPauseOneHour: (() -> Void)?
    var onPauseUntilTomorrow: (() -> Void)?
    var onResume: (() -> Void)?
    var onQuit: (() -> Void)?
    var islandIsExpanded: (() -> Bool)?

    private let preferences: AppPreferences
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
        menu.delegate = self
        setVisible(preferences.menuBarIconVisible)
    }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "capsule", accessibilityDescription: "NotchFlow")
                button.toolTip = "NotchFlow"
            }
            item.menu = menu
            statusItem = item
        } else if !visible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func refreshMenu() {
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusTitle: String
        if let until = preferences.pauseUntil, preferences.isPaused {
            statusTitle = "已暂停至 \(until.formatted(date: .omitted, time: .shortened))"
        } else {
            statusTitle = "NotchFlow 正在运行"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(actionItem("打开设置…", action: #selector(openSettings), key: ","))

        let toggleTitle = islandIsExpanded?() == true ? "收起刘海" : "展开刘海"
        let toggle = actionItem(toggleTitle, action: #selector(toggleIsland), key: "")
        toggle.isEnabled = !preferences.isPaused
        menu.addItem(toggle)

        menu.addItem(.separator())
        if preferences.isPaused {
            menu.addItem(actionItem("立即恢复", action: #selector(resume), key: ""))
        } else {
            menu.addItem(actionItem("暂停 1 小时", action: #selector(pauseOneHour), key: ""))
            menu.addItem(actionItem("暂停至明天", action: #selector(pauseUntilTomorrow), key: ""))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("退出 NotchFlow", action: #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func toggleIsland() { onToggleIsland?() }
    @objc private func pauseOneHour() { onPauseOneHour?() }
    @objc private func pauseUntilTomorrow() { onPauseUntilTomorrow?() }
    @objc private func resume() { onResume?() }
    @objc private func quit() { onQuit?() }
}
