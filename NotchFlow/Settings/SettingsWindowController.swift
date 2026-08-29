import AppKit
import ApplicationServices
import CoreServices
import SwiftUI
import UserNotifications

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(
        preferences: AppPreferences,
        loginItem: LoginItemController,
        timer: TimerController,
        screenService: ScreenGeometryService,
        onShowOnboarding: @escaping () -> Void
    ) {
        let permissionCenter = PermissionCenterModel(timer: timer)
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paimon Pal 设置"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 540, height: 460)
        window.setFrameAutosaveName("NotchFlow.SettingsWindow")

        let hostingView = NSHostingView(rootView: SettingsRootView(
            preferences: preferences,
            loginItem: loginItem,
            permissionCenter: permissionCenter,
            screenService: screenService,
            onShowOnboarding: onShowOnboarding
        ))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case features
    case display
    case permissions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .features: "功能"
        case .display: "显示"
        case .permissions: "权限"
        case .about: "关于"
        }
    }
}

private struct SettingsRootView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var loginItem: LoginItemController
    @ObservedObject var permissionCenter: PermissionCenterModel
    @ObservedObject var screenService: ScreenGeometryService
    let onShowOnboarding: () -> Void
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paimon Pal 设置")
                    .font(.title2.bold())
                Text("v\(versionText) · 本地原生 macOS 工具")
                    .foregroundStyle(.secondary)
            }

            Picker("设置分类", selection: $selection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            ScrollView {
                Group {
                    switch selection {
                    case .general:
                        generalContent
                    case .features:
                        featureContent
                    case .display:
                        displayContent
                    case .permissions:
                        PermissionSettingsView(model: permissionCenter)
                    case .about:
                        aboutContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loginItem.refresh()
            screenService.refreshAvailableDisplays()
        }
    }

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("通用") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("登录后自动启动", isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    Text(loginItem.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Toggle("显示菜单栏图标", isOn: $preferences.menuBarIconVisible)
                    Text("关闭后仍可右键刘海打开设置；暂停期间会自动保留恢复入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("运行状态") {
                HStack(spacing: 12) {
                    Image(systemName: preferences.isPaused ? "pause.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(preferences.isPaused ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preferences.isPaused ? "Paimon Pal 已暂停" : "Paimon Pal 正在运行")
                            .font(.headline)
                        Text(pauseDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if preferences.isPaused {
                        Button("立即恢复") { preferences.resume() }
                    } else {
                        VStack(alignment: .trailing, spacing: 6) {
                            Button("暂停 1 小时") { preferences.pauseForOneHour() }
                            Button("暂停至明天") { preferences.pauseUntilTomorrow() }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var featureContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("各项功能互不依赖。关闭后会停止对应能力，不影响其他功能。")
                .font(.callout)
                .foregroundStyle(.secondary)

            featureToggle(
                "Apple Music",
                description: "读取播放信息、封面、进度并控制播放。",
                icon: "music.note",
                binding: $preferences.musicEnabled
            )
            featureToggle(
                "文件架",
                description: "接收拖入项并保留 Paimon Pal 暂存副本；关闭不删除已有文件。",
                icon: "tray.full",
                binding: $preferences.fileShelfEnabled
            )
            featureToggle(
                "系统状态",
                description: "监听电池、电源、音量和静音变化。",
                icon: "gauge.with.dots.needle.67percent",
                binding: $preferences.systemStatusEnabled
            )
            featureToggle(
                "计时器",
                description: "单计时器倒计时与提醒；关闭时保留未完成的目标时间。",
                icon: "timer",
                binding: $preferences.timerEnabled
            )
            petVoiceSettings
            continuousVoiceSettings
        }
    }

    private var petVoiceSettings: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.and.person.filled")
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("派蒙语音", isOn: $preferences.petVoiceEnabled)
                        .font(.headline)
                    Text("使用内置 P1 清脆反应感固定声线朗读回复和工具结果；关闭时立即停止当前语音。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("完全离线运行，不上传聊天内容，也不会自动下载模型。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("停止播放") {
                    NotificationCenter.default.post(name: .paimonStopVoiceRequested, object: nil)
                }
            }
            .padding(8)
        }
    }

    private var continuousVoiceSettings: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mic.and.signal.meter.fill")
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 对话实验模式")
                        .font(.headline)
                    Text("派蒙会在本机轮流执行收音、语音识别、4B 回复和语音朗读；朗读期间会暂停麦克风，避免听见自己。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("必须手动开启，最多 12 轮或 10 分钟；不保存原始录音，关闭应用后不会自动恢复。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("开启或停止") {
                    NotificationCenter.default.post(
                        name: .paimonToggleContinuousVoiceRequested,
                        object: nil
                    )
                }
            }
            .padding(8)
        }
    }

    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("目标屏幕") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("刘海显示在", selection: displayTargetBinding) {
                        ForEach(DisplayTargetMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if preferences.displayTargetMode == .specific {
                        Picker("指定显示器", selection: specificDisplayBinding) {
                            ForEach(screenService.availableDisplays) { display in
                                Text("\(display.name)（\(display.detail)）")
                                    .tag(display.id)
                            }
                        }
                    }

                    if let resolvedDisplay {
                        Label(
                            "当前目标：\(resolvedDisplay.name) · \(resolvedDisplay.detail)",
                            systemImage: resolvedDisplay.hasNotch ? "laptopcomputer" : "display"
                        )
                        .font(.callout.weight(.medium))
                    } else {
                        Label("暂未检测到可用显示器", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if isSpecificDisplayUnavailable {
                        Text("原指定显示器当前不在线，已临时回退到主显示器；重新连接后会自动恢复。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text("内置屏不可用（例如合盖）或指定屏被拔出时，会自动回退到当前主显示器。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            GroupBox("全屏行为") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("进入全屏时", selection: $preferences.fullScreenBehavior) {
                        ForEach(FullScreenBehavior.allCases) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    Text("“仅显示重要提醒”只保留低电量等严重系统提醒、计时结束和正在接收文件。默认完全隐藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("无刘海显示器微调") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("顶部间距")
                        Slider(value: $preferences.externalDisplayTopOffset, in: 0...40, step: 1)
                        Text("\(Int(preferences.externalDisplayTopOffset)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                    HStack {
                        Text("胶囊宽度")
                        Slider(value: $preferences.floatingCapsuleWidthAdjustment, in: -40...80, step: 2)
                        Text(signedWidthAdjustment)
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                    Text("只影响没有物理刘海的外接屏，不改变 MacBook 刘海的对齐尺寸。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("使用说明") {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("查看首次使用说明")
                            .font(.headline)
                        Text("重新查看刘海操作、四项功能、权限申请和文件副本策略。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开说明…", action: onShowOnboarding)
                }
                .padding(8)
            }

            GroupBox("隐私与数据") {
                VStack(alignment: .leading, spacing: 9) {
                    Label("不采集行为分析，不上传音乐、文件或系统状态。", systemImage: "hand.raised.fill")
                    Label("Apple Music 信息只用于本机显示与控制。", systemImage: "music.note")
                    Label("文件架只访问主动拖入或选择的内容；暂存副本默认保留 24 小时。", systemImage: "folder.badge.gearshape")
                    Label("Finder 原文件不会被 Paimon Pal 移动或删除。", systemImage: "checkmark.shield")
                }
                .font(.callout)
                .padding(8)
            }

            GroupBox("版本与支持范围") {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Paimon Pal（PP）v\(versionText)")
                        .font(.headline)
                    Text("最低支持 macOS 14；当前正式验证设备为 Apple Silicon 刘海屏 MacBook Pro。")
                    Text("音乐首版支持 Apple Music；Spotify 暂缓。屏幕亮度因缺少稳定公开接口而不可用。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(8)
            }
        }
    }

    private func featureToggle(
        _ title: String,
        description: String,
        icon: String,
        binding: Binding<Bool>
    ) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(title, isOn: binding)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        }
    }

    private var pauseDescription: String {
        guard let pauseUntil = preferences.pauseUntil, preferences.isPaused else {
            return "刘海和已启用模块处于正常工作状态。"
        }
        return "将在 \(pauseUntil.formatted(date: .abbreviated, time: .shortened)) 自动恢复。"
    }

    private var displayTargetBinding: Binding<DisplayTargetMode> {
        Binding(
            get: { preferences.displayTargetMode },
            set: { mode in
                preferences.displayTargetMode = mode
                if mode == .specific,
                   preferences.specificDisplayID == nil {
                    preferences.specificDisplayID = screenService.availableDisplays.first?.id
                }
            }
        )
    }

    private var specificDisplayBinding: Binding<String> {
        Binding(
            get: {
                preferences.specificDisplayID
                    ?? screenService.availableDisplays.first?.id
                    ?? ""
            },
            set: { preferences.specificDisplayID = $0 }
        )
    }

    private var resolvedDisplay: DisplayDescriptor? {
        DisplayTargetResolver.resolve(
            from: screenService.availableDisplays,
            mode: preferences.displayTargetMode,
            specificDisplayID: preferences.specificDisplayID
        )
    }

    private var isSpecificDisplayUnavailable: Bool {
        preferences.displayTargetMode == .specific &&
            preferences.specificDisplayID != nil &&
            !screenService.availableDisplays.contains { $0.id == preferences.specificDisplayID }
    }

    private var signedWidthAdjustment: String {
        let value = Int(preferences.floatingCapsuleWidthAdjustment)
        return value > 0 ? "+\(value) pt" : "\(value) pt"
    }

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }
}

@MainActor
private final class PermissionCenterModel: ObservableObject {
    @Published private(set) var accessibilityStatus = "正在检查…"
    @Published private(set) var automationStatus = "正在检查…"
    @Published private(set) var notificationStatus = "正在检查…"
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    private let timer: TimerController

    init(timer: TimerController) {
        self.timer = timer
    }

    func refresh() {
        accessibilityStatus = AXIsProcessTrusted()
            ? "已允许"
            : "未允许（仅影响可选的增强交互）"
        refreshNotifications()
        refreshAutomation()
    }

    func requestNotifications() {
        timer.requestNotificationAuthorization()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.refreshNotifications()
        }
    }

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    func openNotificationSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    private func refreshNotifications() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationAuthorization = settings.authorizationStatus
            notificationStatus = switch settings.authorizationStatus {
            case .authorized: "已允许"
            case .provisional: "已临时允许"
            case .denied: "已拒绝（刘海内提醒仍可用）"
            case .notDetermined: "未请求（使用计时器时可选开启）"
            @unknown default: "状态未知"
            }
        }
    }

    private func refreshAutomation() {
        automationStatus = "正在检查…"
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) { () -> OSStatus in
                let descriptor = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
                guard !NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.Music"
                ).isEmpty,
                let target = descriptor.aeDesc
                else { return OSStatus(procNotFound) }

                return AEDeterminePermissionToAutomateTarget(
                    target,
                    typeWildCard,
                    typeWildCard,
                    false
                )
            }.value
            guard let self else { return }
            automationStatus = Self.automationMessage(for: result)
        }
    }

    nonisolated private static func automationMessage(for status: OSStatus) -> String {
        if status == noErr { return "已允许" }
        if status == OSStatus(errAEEventNotPermitted) {
            return "已拒绝（仅影响 Apple Music）"
        }
        if status == OSStatus(errAEEventWouldRequireUserConsent) {
            return "尚未请求（首次使用音乐时询问）"
        }
        if status == OSStatus(procNotFound) {
            return "Apple Music 未运行，启动后可检查"
        }
        return "暂时无法确认（错误 \(status)）"
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionSettingsView: View {
    @ObservedObject var model: PermissionCenterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("此页只读取当前状态，不会因为打开设置而自动弹出授权框。")
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "辅助功能",
                detail: model.accessibilityStatus,
                explanation: "用于可选的系统 HUD 增强；未授权不影响电池、音量和其他核心功能。",
                buttonTitle: "打开系统设置",
                action: model.openAccessibilitySettings
            )
            permissionRow(
                title: "Apple Music 自动化",
                detail: model.automationStatus,
                explanation: "仅用于读取和控制 Apple Music；拒绝后其他功能仍可用。",
                buttonTitle: "打开系统设置",
                action: model.openAutomationSettings
            )
            permissionRow(
                title: "通知",
                detail: model.notificationStatus,
                explanation: "用于计时结束时的系统通知；未授权时仍会保留刘海内提醒。",
                buttonTitle: notificationButtonTitle,
                action: notificationAction
            )
            permissionRow(
                title: "文件访问",
                detail: "按每次操作授权",
                explanation: "只访问你主动拖入、选择或指定导出的文件，无需全盘访问权限。",
                buttonTitle: nil,
                action: nil
            )

            HStack {
                Text("屏幕亮度：当前不可用（macOS 未向普通第三方 App 提供稳定公开的通用读写接口）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("刷新状态") { model.refresh() }
            }
            .padding(.top, 4)
        }
        .onAppear { model.refresh() }
    }

    private var notificationButtonTitle: String {
        model.notificationAuthorization == .notDetermined
            ? "启用通知…"
            : "打开系统设置"
    }

    private func notificationAction() {
        if model.notificationAuthorization == .notDetermined {
            model.requestNotifications()
        } else {
            model.openNotificationSettings()
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        explanation: String,
        buttonTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(statusColor(detail))
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let buttonTitle, let action {
                    Button(buttonTitle, action: action)
                }
            }
            .padding(8)
        }
    }

    private func statusColor(_ value: String) -> Color {
        if value.hasPrefix("已允许") || value.hasPrefix("已临时允许") {
            return .green
        }
        if value.contains("拒绝") || value.contains("未允许") {
            return .orange
        }
        return .secondary
    }
}
