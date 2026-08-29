import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class LocalPetModelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var draft = ""
    @Published private(set) var messages: [PetConversationMessage] = [
        .init(role: .assistant, text: "嗨，我就在刘海旁边。想说什么都可以，我会陪你聊一会儿。")
    ]
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?

    private let petPanel: NotchPetPanelController
    private let timer: TimerController
    private let preferences: AppPreferences
    private let onOpenUtilityWindow: (UtilitySection) -> Void
    private let onOpenSettings: () -> Void
    private var conversationWindow: NSWindow?

    init(
        petPanel: NotchPetPanelController,
        timer: TimerController,
        preferences: AppPreferences,
        onOpenUtilityWindow: @escaping (UtilitySection) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.petPanel = petPanel
        self.timer = timer
        self.preferences = preferences
        self.onOpenUtilityWindow = onOpenUtilityWindow
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func showConversationPrompt() {
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

    var canSend: Bool {
        !isGenerating && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isGenerating, !prompt.isEmpty else { return }

        let history = messages
        draft = ""
        errorMessage = nil
        messages.append(.init(role: .user, text: prompt))
        petPanel.beginModelSpeaking()

        if let command = PetToolRouter.command(from: prompt) {
            let reply = execute(command)
            messages.append(.init(role: .assistant, text: reply))
            // 工具已经给出了真实的系统反馈。关闭回复后立即让出刘海区域，
            // 避免派蒙成功动画继续遮住计时器等持续活动。
            petPanel.endModelInteraction()
            return
        }

        if let reply = PetConversationRecallResolver.reply(
            history: history,
            latestUserMessage: prompt
        ) {
            messages.append(.init(role: .assistant, text: reply))
            petPanel.finishModelInteractionSuccessfully()
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
                isGenerating = false
                petPanel.finishModelInteractionSuccessfully()
            } catch {
                isGenerating = false
                petPanel.endModelInteraction()
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearConversation() {
        guard !isGenerating else { return }
        messages = [
            .init(role: .assistant, text: "这一段已经清空啦。我们可以从现在重新聊。")
        ]
        errorMessage = nil
    }

    func windowWillClose(_ notification: Notification) {
        petPanel.endModelInteraction()
    }

    private func execute(_ command: PetToolCommand) -> String {
        switch command {
        case .startTimer(let seconds):
            timer.begin(seconds: seconds)
            return "好哒，已经开始计时 \(TimerTextFormatter.duration(seconds: seconds))。"
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

        【最近对话记录】
        \(recentHistory)
        【用户最新一句】
        \(latestUserMessage)
        """
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
    case open(PetToolDestination)
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

        let openKeywords = ["打开", "查看", "看看", "带我去"]
        guard openKeywords.contains(where: text.contains) else { return nil }
        if text.contains("设置") { return .open(.settings) }
        if text.contains("文件架") { return .open(.files) }
        if text.contains("系统状态") { return .open(.system) }
        if text.contains("计时器") { return .open(.timer) }
        if text.contains("音乐") { return .open(.music) }
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
