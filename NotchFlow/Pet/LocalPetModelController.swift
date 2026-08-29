import AppKit
import Foundation

@MainActor
final class LocalPetModelController {
    private let petPanel: NotchPetPanelController
    private let timer: TimerController

    init(petPanel: NotchPetPanelController, timer: TimerController) {
        self.petPanel = petPanel
        self.timer = timer
    }

    func showConversationPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        petPanel.beginModelListening()

        let input = NSTextField(string: "")
        input.placeholderString = "例如：我今天有点累，你能陪陪我吗？"
        input.frame = NSRect(x: 0, y: 0, width: 360, height: 24)

        let alert = NSAlert()
        alert.messageText = "和派蒙聊一句"
        alert.informativeText = "回复由 Mac 内置的本地模型生成，不会上传到网络。"
        alert.accessoryView = input
        alert.addButton(withTitle: "发送")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            petPanel.endModelInteraction()
            return
        }

        let prompt = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            petPanel.endModelInteraction()
            presentError("请先输入一句话。")
            return
        }

        petPanel.beginModelSpeaking()
        if let command = PetToolRouter.command(from: prompt) {
            let reply = execute(command)
            presentReply(reply)
            // 工具已经给出了真实的系统反馈。关闭回复后立即让出刘海区域，
            // 避免派蒙成功动画继续遮住计时器等持续活动。
            petPanel.endModelInteraction()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reply = try await LocalModelRunner.respond(to: prompt)
                presentReply(reply)
                petPanel.finishModelInteractionSuccessfully()
            } catch {
                petPanel.endModelInteraction()
                presentError(error.localizedDescription)
            }
        }
    }

    private func execute(_ command: PetToolCommand) -> String {
        switch command {
        case .startTimer(let seconds):
            timer.begin(seconds: seconds)
            return "好哒，已经开始计时 \(TimerTextFormatter.duration(seconds: seconds))。"
        }
    }

    private func presentReply(_ reply: String) {
        let result = NSAlert()
        result.messageText = "派蒙"
        result.informativeText = reply
        result.addButton(withTitle: "知道啦")
        result.runModal()
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "本地模型暂时无法回复"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

enum PetToolCommand: Equatable {
    case startTimer(seconds: Int)
}

enum PetToolRouter {
    static func command(from input: String) -> PetToolCommand? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let timerKeywords = ["计时", "倒计时", "提醒我"]
        guard timerKeywords.contains(where: text.contains) else { return nil }

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

        let unit = String(text[unitRange])
        let multiplier: Int
        switch unit {
        case "小时", "个小时":
            multiplier = 3_600
        case "分钟", "分":
            multiplier = 60
        case "秒":
            multiplier = 1
        default:
            return nil
        }

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
