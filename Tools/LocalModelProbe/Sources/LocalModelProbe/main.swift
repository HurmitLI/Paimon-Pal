import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@main
struct LocalModelProbe {
    private static let instructions = """
    你是住在 MacBook 刘海旁边的本地桌面助手“派蒙”，只用简体中文。

    回答优先级从高到低：
    1. 直接、准确地解决用户当前问题；严格满足数字、格式、长度、步骤数等明确约束。“X分钟内”表示不得超时；只有用户明确要求合计等于某时长时，步骤时长才必须相加等于该时长。
    2. 结合对话历史解析“这个、那个、第二个、怎么做”等指代，不能丢失上下文。
    3. 语气简洁、温暖、自然，角色感不能代替答案。

    回答前先在内部核对：用户真正问什么、指代什么、有哪些硬性约束；不要输出核对或思考过程。
    原因问题先说原因；具体办法给短步骤；用户指出错误时先承认具体错误，再给修正答案。简单问题一句即可，复杂问题通常两到四句或短步骤。信息不足就说明，不编造，也不机械反问。
    你没有身体，也看不到用户周围的现实环境，不能触碰、观察或代替用户完成现实动作。不得声称自己能拿水杯、确认物品位置、拥抱、拍肩或做其他实体动作，也不要输出括号舞台动作；只能说明能力边界并给出真实可行的替代办法。
    “旅行者”只能偶尔自然使用，不能每次称呼。不要输出角色名称、标签或表情符号。
    """

    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else {
                throw ProbeError.invalidArguments
            }

            let modelDirectory = URL(filePath: arguments[1], directoryHint: .isDirectory)
            let request = try ProbeRequest.parse(arguments: arguments)
            let supportsThinking = !modelDirectory.lastPathComponent.contains("Instruct-2507")
            guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
                throw ProbeError.missingModelDirectory(modelDirectory.path)
            }

            let clock = ContinuousClock()
            let loadStart = clock.now
            let model = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
            let loadDuration = loadStart.duration(to: clock.now)

            let generationStart = clock.now
            var effectiveRequest = request
            if !supportsThinking {
                effectiveRequest.enableThinking = false
            }
            var response = try await generate(
                model: model,
                request: effectiveRequest,
                supportsThinking: supportsThinking
            )
            var cleanedResponse = ResponseSanitizer.clean(response)
            var usedFallback = false

            // 小模型偶尔会把整个额度都花在思考过程上。此时自动用快速模式
            // 重试一次，确保用户得到完整答案而不是空白回复。
            if effectiveRequest.enableThinking && cleanedResponse.isEmpty {
                usedFallback = true
                var fallback = effectiveRequest
                fallback.enableThinking = false
                response = try await generate(
                    model: model,
                    request: fallback,
                    supportsThinking: supportsThinking
                )
                cleanedResponse = ResponseSanitizer.clean(response)
            }

            guard !cleanedResponse.isEmpty else { throw ProbeError.emptyResponse }
            let generationDuration = generationStart.duration(to: clock.now)

            print("MODEL_LOAD_SECONDS=\(loadDuration.secondsText)")
            print("GENERATION_SECONDS=\(generationDuration.secondsText)")
            let reasoningMode = supportsThinking
                ? (effectiveRequest.enableThinking ? "thinking" : "fast")
                : "instruct"
            print("REASONING_MODE=\(reasoningMode)")
            print("REASONING_FALLBACK=\(usedFallback ? "yes" : "no")")
            print("RESPONSE_BEGIN")
            print(cleanedResponse)
            print("RESPONSE_END")
        } catch {
            FileHandle.standardError.write(Data("MODEL_PROBE_ERROR: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func generate(
        model: ModelContainer,
        request: ProbeRequest,
        supportsThinking: Bool
    ) async throws -> String {
        let parameters: GenerateParameters
        if !supportsThinking {
            parameters = GenerateParameters(
                maxTokens: 256,
                temperature: 0.7,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
        } else if request.enableThinking {
            parameters = GenerateParameters(
                maxTokens: 384,
                temperature: 0.5,
                topP: 0.95,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
        } else {
            parameters = GenerateParameters(
                maxTokens: 256,
                temperature: 0.3,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
        }
        let history = request.history.compactMap { message -> Chat.Message? in
            switch message.role {
            case "user": .user(message.content)
            case "assistant": .assistant(message.content)
            default: nil
            }
        }
        let session = ChatSession(
            model,
            instructions: instructions,
            history: history,
            generateParameters: parameters
        )
        let prompt: String
        if supportsThinking {
            let mode = request.enableThinking ? "/think" : "/no_think"
            prompt = "\(request.prompt) \(mode)"
        } else {
            prompt = request.prompt
        }
        return try await session.respond(to: prompt)
    }
}

private struct ProbeRequest: Codable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let history: [Message]
    let prompt: String
    var enableThinking: Bool

    static func parse(arguments: [String]) throws -> Self {
        if arguments.count == 4, arguments[2] == "--request-base64" {
            guard let data = Data(base64Encoded: arguments[3]) else {
                throw ProbeError.invalidRequest
            }
            return try JSONDecoder().decode(Self.self, from: data)
        }

        // 保留命令行探针的旧用法，方便独立验证模型。
        return Self(
            history: [],
            prompt: arguments.dropFirst(2).joined(separator: " "),
            enableThinking: false
        )
    }
}

private enum ResponseSanitizer {
    static func clean(_ response: String) -> String {
        var cleaned = response.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        // 生成额度耗尽时可能只留下未闭合的 <think>，不能把内部思考显示给用户。
        if let unfinishedThinking = cleaned.range(of: "<think>") {
            cleaned.removeSubrange(unfinishedThinking.lowerBound..<cleaned.endIndex)
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ProbeError: LocalizedError {
    case invalidArguments
    case invalidRequest
    case missingModelDirectory(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "用法：notchflow-model-probe <模型目录> <问题>"
        case .invalidRequest:
            "模型请求格式无效。"
        case .missingModelDirectory(let path):
            "找不到模型目录：\(path)"
        case .emptyResponse:
            "模型没有生成有效回复。"
        }
    }
}

private extension Duration {
    var secondsText: String {
        let components = self.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.3f", seconds)
    }
}
