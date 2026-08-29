import AppKit
import Combine
import Foundation
import SwiftUI

enum PetTimerSpeechPolicy {
    static func shouldSpeak(previous: CountdownPhase, current: CountdownPhase) -> Bool {
        previous == .running && current == .ringing
    }
}

@MainActor
final class LocalPetModelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var draft = ""
    @Published private(set) var messages: [PetConversationMessage] = [
        .init(role: .assistant, text: "嗨，我就在刘海旁边。想说什么都可以，我会陪你聊一会儿。")
    ]
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var quickReply: String?
    @Published private(set) var quickPromptFocusRequest = UUID()

    private let petPanel: NotchPetPanelController
    private let timer: TimerController
    private let music: MusicController
    private let preferences: AppPreferences
    private let speech: PetSpeechController
    private let onOpenUtilityWindow: (UtilitySection) -> Void
    private let onOpenSettings: () -> Void
    private var conversationWindow: NSWindow?
    private var quickPromptWindow: PetQuickPromptPanel?
    private var lastTimerPhase: CountdownPhase
    private var cancellables: Set<AnyCancellable> = []

    init(
        petPanel: NotchPetPanelController,
        timer: TimerController,
        music: MusicController,
        preferences: AppPreferences,
        speechController: PetSpeechController? = nil,
        onOpenUtilityWindow: @escaping (UtilitySection) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.petPanel = petPanel
        self.timer = timer
        self.music = music
        self.preferences = preferences
        speech = speechController ?? PetSpeechController(preferences: preferences)
        lastTimerPhase = timer.state.phase
        self.onOpenUtilityWindow = onOpenUtilityWindow
        self.onOpenSettings = onOpenSettings
        super.init()

        Publishers.CombineLatest3($isGenerating, $quickReply, $errorMessage)
            .dropFirst()
            .sink { [weak self] _ in self?.refreshQuickPromptFrame() }
            .store(in: &cancellables)

        preferences.$petVoiceEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                guard !enabled else { return }
                self?.speech.stop()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .paimonStopVoiceRequested)
            .sink { [weak self] _ in self?.speech.stop() }
            .store(in: &cancellables)

        timer.$state
            .map(\.phase)
            .removeDuplicates()
            .sink { [weak self] phase in
                guard let self else { return }
                let previousPhase = lastTimerPhase
                lastTimerPhase = phase
                guard PetTimerSpeechPolicy.shouldSpeak(
                    previous: previousPhase,
                    current: phase
                ) else { return }
                speakTimerFinishedReminder()
            }
            .store(in: &cancellables)
    }

    func showQuickPrompt() {
        conversationWindow?.orderOut(nil)
        quickReply = nil
        errorMessage = nil
        quickPromptFocusRequest = UUID()

        let window = quickPromptWindow ?? makeQuickPromptWindow()
        quickPromptWindow = window
        refreshQuickPromptFrame()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !isGenerating {
            petPanel.beginQuickPromptListening()
        }
    }

    func showConversationPrompt() {
        quickPromptWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        let window = conversationWindow ?? makeConversationWindow()
        conversationWindow = window
        window.center()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        if !isGenerating {
            petPanel.beginModelListening()
        }
    }

    func closeQuickPrompt() {
        quickPromptWindow?.orderOut(nil)
        speech.stop()
        if !isGenerating {
            petPanel.endModelInteraction()
        }
    }

    func showFullConversationFromQuickPrompt() {
        showConversationPrompt()
    }

    func repositionQuickPrompt() {
        guard quickPromptWindow?.isVisible == true else { return }
        refreshQuickPromptFrame()
    }

    var canSend: Bool {
        !isGenerating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !prompt.isEmpty else { return }

        speech.stop(notifyCompletion: false)
        let history = messages
        draft = ""
        errorMessage = nil
        quickReply = nil
        messages.append(.init(role: .user, text: prompt))
        petPanel.beginModelListening()

        if let command = PetToolRouter.command(from: prompt) {
            let reply = execute(command)
            messages.append(.init(role: .assistant, text: reply))
            quickReply = reply
            // 工具已经给出了真实的系统反馈。关闭回复后立即让出刘海区域，
            // 避免派蒙成功动画继续遮住计时器等持续活动。
            petPanel.endModelInteraction()
            speak(reply, completion: .yieldToIsland)
            return
        }

        if let reply = PetConversationRecallResolver.reply(
            history: history,
            latestUserMessage: prompt
        ) {
            messages.append(.init(role: .assistant, text: reply))
            quickReply = reply
            speak(reply, completion: .celebrate)
            return
        }

        if let reply = PetConversationBehaviorFeedbackResolver.reply(
            latestUserMessage: prompt
        ) {
            messages.append(.init(role: .assistant, text: reply))
            quickReply = reply
            speak(reply, completion: .celebrate)
            return
        }

        isGenerating = true
        let contextualPrompt = PetConversationContextBuilder.prompt(
            history: history,
            latestUserMessage: prompt
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reply = try await LocalModelRunner.respond(to: contextualPrompt)
                messages.append(.init(role: .assistant, text: reply))
                quickReply = reply
                isGenerating = false
                speak(reply, completion: .celebrate)
            } catch {
                isGenerating = false
                petPanel.endModelInteraction()
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearConversation() {
        guard !isGenerating else { return }
        speech.stop(notifyCompletion: false)
        messages = [
            .init(role: .assistant, text: "这一段已经清空啦。我们可以从现在重新聊。")
        ]
        quickReply = nil
        errorMessage = nil
    }

    func windowWillClose(_ notification: Notification) {
        speech.stop()
        petPanel.endModelInteraction()
    }

    func stopSpeech() {
        speech.stop()
    }

    private enum SpeechCompletion {
        case celebrate
        case yieldToIsland
    }

    private func speak(_ reply: String, completion: SpeechCompletion) {
        let scheduled = speech.speak(
            reply,
            onPlaybackStarted: { [weak self] in
                self?.petPanel.beginModelSpeaking()
            },
            onFinished: { [weak self] in
                guard let self else { return }
                switch completion {
                case .celebrate:
                    petPanel.finishModelInteractionSuccessfully()
                case .yieldToIsland:
                    petPanel.endModelInteraction()
                }
            }
        )
        guard !scheduled else { return }
        switch completion {
        case .celebrate:
            petPanel.finishModelInteractionSuccessfully()
        case .yieldToIsland:
            petPanel.endModelInteraction()
        }
    }

    private func speakTimerFinishedReminder() {
        speech.stop(notifyCompletion: false)
        let scheduled = speech.speak(
            "时间到啦！快回来看看吧。",
            onPlaybackStarted: { [weak self] in self?.petPanel.beginModelSpeaking() },
            onFinished: { [weak self] in self?.petPanel.endModelInteraction() }
        )
        if !scheduled {
            petPanel.endModelInteraction()
        }
    }

    private func execute(_ command: PetToolCommand) -> String {
        switch command {
        case .startTimer(let seconds):
            timer.begin(seconds: seconds)
            return "好哒，已经开始计时 \(TimerTextFormatter.duration(seconds: seconds))。"
        case .timer(let action):
            return PetTimerToolExecutor.execute(action, timer: timer)
        case .music(let action):
            return PetMusicToolExecutor.execute(
                action,
                music: music,
                isEnabled: preferences.musicEnabled,
                onOpenSettings: onOpenSettings
            )
        case .open(let destination):
            return open(destination)
        }
    }

    private func open(_ destination: PetToolDestination) -> String {
        switch destination {
        case .settings:
            onOpenSettings()
            return "好哒，已经打开 Paimon Pal 设置。"
        case .music:
            return openUtility(.music, isEnabled: preferences.musicEnabled, title: "音乐")
        case .files:
            return openUtility(.files, isEnabled: preferences.fileShelfEnabled, title: "文件架")
        case .system:
            return openUtility(.system, isEnabled: preferences.systemStatusEnabled, title: "系统状态")
        case .timer:
            return openUtility(.timer, isEnabled: preferences.timerEnabled, title: "计时器")
        }
    }

    private func openUtility(
        _ section: UtilitySection,
        isEnabled: Bool,
        title: String
    ) -> String {
        guard isEnabled else {
            onOpenSettings()
            return "\(title)功能目前是关闭的，我已经打开设置，你可以先把它开启。"
        }
        onOpenUtilityWindow(section)
        return "好哒，已经打开 Paimon Pal \(title)窗口。"
    }

    private func makeConversationWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "派蒙 · 本地陪伴"
        window.minSize = NSSize(width: 380, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: PetConversationView(controller: self))
        return window
    }

    private func makeQuickPromptWindow() -> PetQuickPromptPanel {
        let window = PetQuickPromptPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.animationBehavior = .none
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PetQuickPromptView(controller: self))
        return window
    }

    private func refreshQuickPromptFrame() {
        guard let window = quickPromptWindow else { return }
        let size = PetQuickPromptLayout.preferredSize(
            isGenerating: isGenerating,
            reply: quickReply,
            errorMessage: errorMessage
        )
        let frame = PetQuickPromptLayout.frame(
            anchorFrame: petPanel.presentationFrame,
            panelSize: size,
            visibleFrame: petPanel.presentationVisibleFrame
        )
        window.setFrame(frame, display: window.isVisible)
    }
}

final class PetQuickPromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PetQuickPromptLayout {
    static let horizontalGap: CGFloat = 12

    static func preferredSize(
        isGenerating: Bool,
        reply: String?,
        errorMessage: String?
    ) -> CGSize {
        let hasFeedback = isGenerating || reply != nil || errorMessage != nil
        return CGSize(width: 360, height: hasFeedback ? 154 : 66)
    }

    static func frame(
        anchorFrame: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let rightX = anchorFrame.maxX + horizontalGap
        let leftX = anchorFrame.minX - horizontalGap - panelSize.width
        let fitsRight = rightX + panelSize.width <= visibleFrame.maxX
        let fitsLeft = leftX >= visibleFrame.minX

        let preferredX: CGFloat
        if fitsRight || !fitsLeft {
            preferredX = rightX
        } else {
            preferredX = leftX
        }

        let proposed = CGRect(
            x: preferredX,
            y: anchorFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        return PetDesktopPlacementCalculator.constrainedFrame(proposed, inside: visibleFrame)
    }
}

enum PetConversationRole: String, Equatable {
    case user
    case assistant
}

struct PetConversationMessage: Identifiable, Equatable {
    let id: UUID
    let role: PetConversationRole
    let text: String

    init(id: UUID = UUID(), role: PetConversationRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum PetConversationRecallResolver {
    static func reply(
        history: [PetConversationMessage],
        latestUserMessage: String
    ) -> String? {
        let normalized = latestUserMessage
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let recallPatterns = [
            #"我(?:刚才|刚刚|之前|前面).*说.*(?:什么|怎么)"#,
            #"还记得我.*说"#
        ]
        guard recallPatterns.contains(where: {
            normalized.range(of: $0, options: .regularExpression) != nil
        }) else {
            return nil
        }

        guard let previousUserMessage = history.last(where: { $0.role == .user }) else {
            return "这段对话已经清空啦，我现在没有可以回看的内容。"
        }
        let recalledText = previousUserMessage.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(160)
        return "你刚才说“\(recalledText)”呀。"
    }
}

enum PetConversationBehaviorFeedbackResolver {
    static func reply(latestUserMessage: String) -> String? {
        let normalized = latestUserMessage
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        guard normalized.contains("旅行者") else { return nil }

        let repetitionTerms = ["每次", "每一句", "每句话", "每句", "总是", "一直", "都会", "都加"]
        let feedbackTerms = ["好像", "是吧", "是不是", "为什么", "怎么", "别", "不要", "不用"]
        guard repetitionTerms.contains(where: normalized.contains),
              feedbackTerms.contains(where: normalized.contains)
        else { return nil }

        return "你发现得没错，刚才语音会固定加上“旅行者”，听起来确实很重复。以后我只会在合适的时候偶尔这样称呼，不会每句话都加啦。"
    }
}

enum PetConversationContextBuilder {
    private static let maximumHistoryMessages = 6
    private static let maximumCharactersPerMessage = 320

    static func prompt(
        history: [PetConversationMessage],
        latestUserMessage: String
    ) -> String {
        let recentHistory = history
            .suffix(maximumHistoryMessages)
            .map { message in
                let speaker = message.role == .user ? "用户" : "派蒙"
                let normalized = message.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(maximumCharactersPerMessage)
                return "\(speaker)：\(normalized)"
            }
            .joined(separator: "\n")

        guard !recentHistory.isEmpty else { return latestUserMessage }
        return """
        【任务】只回答“用户最新一句”。回答前必须先阅读“最近对话记录”，并自然承接其中的信息。
        【上下文规则】如果用户询问自己刚才说过什么、之前发生了什么，必须从记录中找到对应内容并直接准确回答；不得猜测、回避，也不得说用户讲错了。只有记录里确实没有答案时，才说明不记得。
        【表达规则】通常不要机械复述整段记录，但用户明确询问前文时，可以准确复述相关内容。
        【反馈规则】如果用户正在评价、质疑或纠正你的用词与行为，必须先直接判断用户说得是否正确，再回应如何调整；不得把其中的关键词误当成新的角色扮演话题，不得转移问题。

        【最近对话记录】
        \(recentHistory)
        【用户最新一句】
        \(latestUserMessage)
        """
    }
}

private struct PetQuickPromptView: View {
    @ObservedObject var controller: LocalPetModelController
    @FocusState private var inputIsFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if controller.isGenerating {
                feedbackCard {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("派蒙正在想……")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else if let reply = controller.quickReply {
                feedbackCard {
                    Text(reply)
                        .font(.callout)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let error = controller.errorMessage {
                feedbackCard {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 8) {
                Button(action: controller.showFullConversationFromQuickPrompt) {
                    Image(systemName: "text.bubble")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("打开完整对话")
                .accessibilityLabel("打开完整对话")

                TextField("问派蒙一句……", text: $controller.draft)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($inputIsFocused)
                    .onSubmit { controller.sendDraft() }

                Button(action: controller.sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.canSend ? Color.accentColor : .secondary)
                .disabled(!controller.canSend)
                .accessibilityLabel("发送")

                Button(action: controller.closeQuickPrompt) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.88),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .onAppear { requestFocus() }
        .onChange(of: controller.quickPromptFocusRequest) { requestFocus() }
    }

    private func feedbackCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                Color(nsColor: .windowBackgroundColor).opacity(0.94),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
    }

    private func requestFocus() {
        DispatchQueue.main.async {
            inputIsFocused = true
        }
    }
}

private struct PetConversationView: View {
    @ObservedObject var controller: LocalPetModelController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(minWidth: 380, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("派蒙")
                    .font(.headline)
                Text("住在刘海旁的本地小伙伴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("仅本机", systemImage: "lock.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(controller.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if controller.isGenerating {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("派蒙正在想……")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .id("generating")
                    }
                    if let error = controller.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
            .onChange(of: controller.messages.count) {
                scrollToLatest(using: proxy)
            }
            .onChange(of: controller.isGenerating) {
                scrollToLatest(using: proxy)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "说点什么，例如：我今天有点累",
                    text: $controller.draft,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { controller.sendDraft() }

                Button(action: controller.sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.canSend ? Color.accentColor : .secondary)
                .disabled(!controller.canSend)
                .accessibilityLabel("发送")
            }

            HStack {
                Text("最多携带最近 6 条消息；关闭应用后不会保留。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空本次对话", action: controller.clearConversation)
                    .font(.caption)
                    .disabled(controller.isGenerating)
            }
        }
        .padding(14)
    }

    private func messageBubble(_ message: PetConversationMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 54) }
            Text(message.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                .background(
                    message.role == .user ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            if message.role == .assistant { Spacer(minLength: 54) }
        }
        .frame(maxWidth: .infinity)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        let target: AnyHashable? = controller.isGenerating
            ? AnyHashable("generating")
            : controller.messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

enum PetToolCommand: Equatable {
    case startTimer(seconds: Int)
    case timer(PetTimerAction)
    case music(PetMusicAction)
    case open(PetToolDestination)
}

enum PetTimerAction: Equatable {
    case pause
    case resume
    case cancel
    case status
}

enum PetMusicAction: Equatable {
    case play
    case pause
    case next
    case previous
    case status
}

@MainActor
enum PetTimerToolExecutor {
    static func execute(_ action: PetTimerAction, timer: TimerController) -> String {
        switch action {
        case .pause:
            guard timer.state.phase == .running else {
                return stateReply(timer: timer, requestedAction: "暂停")
            }
            timer.pause()
            return "好哒，计时已暂停，还剩 \(TimerTextFormatter.duration(seconds: timer.remainingSeconds))。"
        case .resume:
            guard timer.state.phase == .paused else {
                return stateReply(timer: timer, requestedAction: "继续")
            }
            timer.resume()
            return "好哒，继续计时，还剩 \(TimerTextFormatter.duration(seconds: timer.remainingSeconds))。"
        case .cancel:
            guard timer.state.phase != .idle else {
                return "现在没有正在运行的计时。"
            }
            timer.cancel()
            return "好哒，这次计时已经取消。"
        case .status:
            return stateReply(timer: timer, requestedAction: nil)
        }
    }

    private static func stateReply(
        timer: TimerController,
        requestedAction: String?
    ) -> String {
        switch timer.state.phase {
        case .idle:
            return "现在没有正在运行的计时。"
        case .running:
            let prefix = requestedAction == "暂停" ? "计时还在运行，" : "计时正在进行，"
            return "\(prefix)还剩 \(TimerTextFormatter.duration(seconds: timer.remainingSeconds))。"
        case .paused:
            let prefix = requestedAction == "继续" ? "计时已经暂停，" : "计时处于暂停状态，"
            return "\(prefix)还剩 \(TimerTextFormatter.duration(seconds: timer.remainingSeconds))。"
        case .ringing:
            return "这次计时已经结束，正在等待你确认。"
        }
    }
}

@MainActor
enum PetMusicToolExecutor {
    static func execute(
        _ action: PetMusicAction,
        music: MusicController,
        isEnabled: Bool,
        onOpenSettings: () -> Void
    ) -> String {
        guard isEnabled else {
            onOpenSettings()
            return "音乐功能目前是关闭的，我已经打开设置，你可以先把它开启。"
        }

        music.refresh()
        if let error = music.lastError {
            return "无法读取 Apple Music：\(error.localizedDescription)"
        }
        if action == .status {
            return stateReply(snapshot: music.snapshot)
        }
        if action != .play, !music.snapshot.running {
            return "Apple Music 还没有运行，我没有执行这条播放指令。"
        }

        let command: MusicCommand
        let successReply: String
        switch action {
        case .play:
            if music.snapshot.playbackState == .playing {
                return stateReply(snapshot: music.snapshot)
            }
            command = .play
            successReply = "好哒，已经向 Apple Music 发送播放指令。"
        case .pause:
            if music.snapshot.playbackState == .paused {
                return "Apple Music 已经暂停了。"
            }
            command = .pause
            successReply = "好哒，已经向 Apple Music 发送暂停指令。"
        case .next:
            command = .next
            successReply = "好哒，已经向 Apple Music 发送切换下一首指令。"
        case .previous:
            command = .previous
            successReply = "好哒，已经向 Apple Music 发送切换上一首指令。"
        case .status:
            return stateReply(snapshot: music.snapshot)
        }

        switch music.send(command) {
        case .success:
            return successReply
        case .failure(let error):
            return "没有执行成功：\(error.localizedDescription)"
        }
    }

    private static func stateReply(snapshot: MusicSnapshot) -> String {
        guard snapshot.installed else { return "这台 Mac 没有找到 Apple Music。" }
        guard snapshot.running else { return "Apple Music 目前没有运行。" }
        guard !snapshot.title.isEmpty else {
            return snapshot.playbackState == .paused
                ? "Apple Music 已暂停，目前没有可显示的歌曲信息。"
                : "Apple Music 当前没有播放歌曲。"
        }
        let stateText = snapshot.playbackState == .playing ? "正在播放" : "目前暂停在"
        let artistText = snapshot.artist.isEmpty ? "" : "，歌手是 \(snapshot.artist)"
        return "Apple Music \(stateText)《\(snapshot.title)》\(artistText)。"
    }
}

enum PetToolDestination: Equatable {
    case settings
    case music
    case files
    case system
    case timer
}

enum PetToolRouter {
    static func command(from input: String) -> PetToolCommand? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let timerKeywords = ["计时", "倒计时", "提醒我"]
        if timerKeywords.contains(where: text.contains),
           let timer = timerCommand(from: text) {
            return timer
        }

        if let timerAction = timerAction(from: text) {
            return .timer(timerAction)
        }
        if let musicAction = musicAction(from: text) {
            return .music(musicAction)
        }

        let openKeywords = ["打开", "查看", "看看", "带我去"]
        guard openKeywords.contains(where: text.contains) else { return nil }
        if text.contains("设置") { return .open(.settings) }
        if text.contains("文件架") { return .open(.files) }
        if text.contains("系统状态") { return .open(.system) }
        if text.contains("计时器") { return .open(.timer) }
        if text.contains("音乐") { return .open(.music) }
        return nil
    }

    private static func timerAction(from text: String) -> PetTimerAction? {
        guard text.contains("计时") || text.contains("倒计时") else { return nil }
        if ["取消", "停止", "结束", "关掉"].contains(where: text.contains) {
            return .cancel
        }
        if ["继续", "恢复"].contains(where: text.contains) {
            return .resume
        }
        if ["暂停", "停一下"].contains(where: text.contains) {
            return .pause
        }
        if ["还剩", "多久", "状态", "进度"].contains(where: text.contains) {
            return .status
        }
        return nil
    }

    private static func musicAction(from text: String) -> PetMusicAction? {
        if text == "下一首" || text.contains("下一首歌") || text.contains("切到下一首") || text.contains("换一首歌") {
            return .next
        }
        if text == "上一首" || text.contains("上一首歌") || text.contains("切到上一首") {
            return .previous
        }
        if text.contains("音乐") || text.contains("歌曲") || text.contains("什么歌") {
            if ["暂停", "停一下"].contains(where: text.contains) { return .pause }
            if ["继续播放", "开始播放", "播放音乐", "放点音乐"].contains(where: text.contains) {
                return .play
            }
            if ["什么歌", "当前歌曲", "播放状态", "音乐状态"].contains(where: text.contains) {
                return .status
            }
        }
        return nil
    }

    private static func timerCommand(from text: String) -> PetToolCommand? {
        let pattern = #"(\d{1,5})\s*(个?小时|分钟|分|秒)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let amountRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let amount = Int(text[amountRange])
        else { return nil }

        let multiplier = switch String(text[unitRange]) {
        case "小时", "个小时": 3_600
        case "分钟", "分": 60
        case "秒": 1
        default: 0
        }
        guard multiplier > 0 else { return nil }

        let (seconds, overflow) = amount.multipliedReportingOverflow(by: multiplier)
        guard !overflow, (1...359_999).contains(seconds) else { return nil }
        return .startTimer(seconds: seconds)
    }
}

private enum LocalModelRunner {
    static func respond(to prompt: String) async throws -> String {
        let runtime = try LocalModelRuntime.locate()
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = runtime.executable
            process.arguments = [runtime.modelDirectory.path, prompt]
            process.currentDirectoryURL = runtime.resourceDirectory
            process.standardOutput = standardOutput
            process.standardError = standardError

            try process.run()
            process.waitUntilExit()

            let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: outputData, as: UTF8.self)
            let errorOutput = String(decoding: errorData, as: UTF8.self)

            guard process.terminationStatus == 0 else {
                let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                throw LocalModelError.runtimeFailed(message.isEmpty ? "模型进程异常退出。" : message)
            }
            return try parseResponse(output)
        }.value
    }

    private static func parseResponse(_ output: String) throws -> String {
        let startMarker = "RESPONSE_BEGIN\n"
        let endMarker = "\nRESPONSE_END"
        guard let start = output.range(of: startMarker)?.upperBound,
              let end = output.range(of: endMarker, range: start..<output.endIndex)?.lowerBound
        else {
            throw LocalModelError.invalidResponse
        }

        let reply = output[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw LocalModelError.invalidResponse }
        return reply
    }
}

private struct LocalModelRuntime: Sendable {
    let executable: URL
    let modelDirectory: URL
    let resourceDirectory: URL

    static func locate(bundle: Bundle = .main) throws -> LocalModelRuntime {
        guard let resourceDirectory = bundle.resourceURL,
              let executable = bundle.url(forResource: "notchflow-model-probe", withExtension: nil),
              let modelDirectory = bundle.url(
                forResource: "Qwen3-1.7B-4bit",
                withExtension: nil
              )
        else {
            throw LocalModelError.missingBundledRuntime
        }
        return LocalModelRuntime(
            executable: executable,
            modelDirectory: modelDirectory,
            resourceDirectory: resourceDirectory
        )
    }
}

private enum LocalModelError: LocalizedError {
    case missingBundledRuntime
    case runtimeFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingBundledRuntime:
            "安装包中缺少本地模型或推理组件。"
        case .runtimeFailed(let message):
            "模型运行失败：\(message)"
        case .invalidResponse:
            "模型返回了无法识别的内容。"
        }
    }
}
