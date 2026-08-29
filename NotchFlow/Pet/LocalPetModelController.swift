import AppKit
import Foundation

@MainActor
final class LocalPetModelController {
    private let petPanel: NotchPetPanelController

    init(petPanel: NotchPetPanelController) {
        self.petPanel = petPanel
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let reply = try await LocalModelRunner.respond(to: prompt)
                let result = NSAlert()
                result.messageText = "派蒙"
                result.informativeText = reply
                result.addButton(withTitle: "知道啦")
                result.runModal()
                petPanel.finishModelInteractionSuccessfully()
            } catch {
                petPanel.endModelInteraction()
                presentError(error.localizedDescription)
            }
        }
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
