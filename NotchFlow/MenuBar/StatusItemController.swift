import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onOpenWorkspace: (() -> Void)?
    var onToggleIsland: (() -> Void)?
    var onPauseOneHour: (() -> Void)?
    var onPauseUntilTomorrow: (() -> Void)?
    var onResume: (() -> Void)?
    var onQuit: (() -> Void)?
    var islandIsExpanded: (() -> Bool)?
    var onToggleContinuousVoice: (() -> Void)?
    var continuousVoicePhase: (() -> PetContinuousVoicePhase)?
#if DEBUG
    var onTestLocalModelConversation: (() -> Void)?
    var onTogglePetListening: (() -> Void)?
    var petIsListening: (() -> Bool)?
    var onTogglePetSpeaking: (() -> Void)?
    var petIsSpeaking: (() -> Bool)?
    var onTestPetSuccess: (() -> Void)?
#endif

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
                button.image = Self.menuBarImage()
                    ?? NSImage(
                        systemSymbolName: "person.crop.circle",
                        accessibilityDescription: "Paimon Pal"
                    )
                button.toolTip = "Paimon Pal（PP）"
            }
            item.menu = menu
            statusItem = item
        } else if !visible, let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    static func menuBarImage(bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(
            forResource: "PaimonMenuBarIconTemplate",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        // 彩色头像需要保留金色光环、白发和蓝紫眼睛；Template 模式会把它
        // 强制染成单色，重新变成用户已经否决的抽象符号。
        image.isTemplate = false
        image.accessibilityDescription = "Paimon Pal"
        return image
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
            statusTitle = "Paimon Pal 正在运行"
        }
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(actionItem("打开设置…", action: #selector(openSettings), key: ","))
        menu.addItem(actionItem("打开工作台…", action: #selector(openWorkspace), key: "w"))

        let toggleTitle = islandIsExpanded?() == true ? "收起刘海" : "展开刘海"
        let toggle = actionItem(toggleTitle, action: #selector(toggleIsland), key: "")
        toggle.isEnabled = !preferences.isPaused
        menu.addItem(toggle)

        let voicePhase = continuousVoicePhase?() ?? .idle
        let voiceTitle = voicePhase.isActive
            ? "停止 AI 对话实验模式"
            : "开启 AI 对话实验模式"
        let continuousVoice = actionItem(
            voiceTitle,
            action: #selector(toggleContinuousVoice),
            key: ""
        )
        continuousVoice.isEnabled = !preferences.isPaused || voicePhase.isActive
        menu.addItem(continuousVoice)
        if voicePhase != .idle {
            let phaseStatus = NSMenuItem(
                title: "语音状态：\(voicePhase.displayName)",
                action: nil,
                keyEquivalent: ""
            )
            phaseStatus.isEnabled = false
            menu.addItem(phaseStatus)
        }

#if DEBUG
        let localModelConversation = actionItem(
            "测试内置模型对话…",
            action: #selector(testLocalModelConversation),
            key: ""
        )
        localModelConversation.isEnabled = !preferences.isPaused
        menu.addItem(localModelConversation)

        let listeningTitle = petIsListening?() == true
            ? "结束派蒙聆听测试"
            : "测试派蒙聆听"
        let listening = actionItem(
            listeningTitle,
            action: #selector(togglePetListening),
            key: ""
        )
        listening.isEnabled = !preferences.isPaused
        menu.addItem(listening)

        let speakingTitle = petIsSpeaking?() == true
            ? "结束派蒙说话测试"
            : "测试派蒙说话"
        let speaking = actionItem(
            speakingTitle,
            action: #selector(togglePetSpeaking),
            key: ""
        )
        speaking.isEnabled = !preferences.isPaused
        menu.addItem(speaking)

        let success = actionItem(
            "测试派蒙成功反馈",
            action: #selector(testPetSuccess),
            key: ""
        )
        success.isEnabled = !preferences.isPaused
        menu.addItem(success)
#endif

        menu.addItem(.separator())
        if preferences.isPaused {
            menu.addItem(actionItem("立即恢复", action: #selector(resume), key: ""))
        } else {
            menu.addItem(actionItem("暂停 1 小时", action: #selector(pauseOneHour), key: ""))
            menu.addItem(actionItem("暂停至明天", action: #selector(pauseUntilTomorrow), key: ""))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("退出 Paimon Pal", action: #selector(quit), key: "q"))
    }

    private func actionItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openWorkspace() { onOpenWorkspace?() }
    @objc private func toggleIsland() { onToggleIsland?() }
    @objc private func toggleContinuousVoice() { onToggleContinuousVoice?() }
    @objc private func pauseOneHour() { onPauseOneHour?() }
    @objc private func pauseUntilTomorrow() { onPauseUntilTomorrow?() }
    @objc private func resume() { onResume?() }
    @objc private func quit() { onQuit?() }
#if DEBUG
    @objc private func testLocalModelConversation() { onTestLocalModelConversation?() }
    @objc private func togglePetListening() { onTogglePetListening?() }
    @objc private func togglePetSpeaking() { onTogglePetSpeaking?() }
    @objc private func testPetSuccess() { onTestPetSuccess?() }
#endif
}
