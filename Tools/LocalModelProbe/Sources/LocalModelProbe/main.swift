import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@main
struct LocalModelProbe {
    private static let instructions = """
    你是住在 MacBook 刘海旁边的桌面伙伴，名字叫派蒙。你必须使用简体中文。
    你是一名能认真回答问题、解释原因并提供办法的本地助手，不是只负责安慰和倾听的玩偶。解决用户问题是第一职责，陪伴感只是表达语气。绝不能以“我的职责是陪伴”为理由回避问题。
    首要任务是准确理解并直接回答用户当前真正想问的内容，再自然地保持温暖、活泼的语气；不能用陪伴套话代替答案。第一句话就要进入答案，不要先寒暄。
    要结合对话历史理解“这个”“那样”“怎么做”等指代和追问。用户纠正、质疑你的回答或行为时，先正面判断问题，再说明如何调整，不得转移话题。
    简单问题可以只答一句；需要解释时通常回答两到四句，并尽量给出具体、可执行的信息。信息不足时明确说明，不要编造。
    用户询问原因时先明确说出原因；用户要求具体办法时给出短步骤；用户批评回答时先承认或澄清具体问题，再给出调整后的答案。
    不要把用户的经历说成自己的经历，不要说教，也不要为了活泼而机械反问。除非缺少关键信息，否则不要用问题结尾。
    你没有身体，不能触碰、观察或代替用户做现实动作；不要描写拍肩、拥抱、递东西等虚构动作，也不要输出括号舞台动作。
    “旅行者”只在语境自然时偶尔使用，不能每次都称呼。
    不要输出思考过程、标签或角色名称。
    """

    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else {
                throw ProbeError.invalidArguments
            }

            let modelDirectory = URL(filePath: arguments[1], directoryHint: .isDirectory)
            let request = try ProbeRequest.parse(arguments: arguments)
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
            var response = try await generate(model: model, request: request)
            var cleanedResponse = ResponseSanitizer.clean(response)
            var usedFallback = false

            // 小模型偶尔会把整个额度都花在思考过程上。此时自动用快速模式
            // 重试一次，确保用户得到完整答案而不是空白回复。
            if request.enableThinking && cleanedResponse.isEmpty {
                usedFallback = true
                var fallback = request
                fallback.enableThinking = false
                response = try await generate(model: model, request: fallback)
                cleanedResponse = ResponseSanitizer.clean(response)
            }

            guard !cleanedResponse.isEmpty else { throw ProbeError.emptyResponse }
            let generationDuration = generationStart.duration(to: clock.now)

            print("MODEL_LOAD_SECONDS=\(loadDuration.secondsText)")
            print("GENERATION_SECONDS=\(generationDuration.secondsText)")
            print("REASONING_MODE=\(request.enableThinking ? "thinking" : "fast")")
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
        request: ProbeRequest
    ) async throws -> String {
        let parameters = request.enableThinking
            ? GenerateParameters(
                maxTokens: 512,
                temperature: 0.6,
                topP: 0.95,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
            : GenerateParameters(
                maxTokens: 192,
                temperature: 0.5,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
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
        let mode = request.enableThinking ? "/think" : "/no_think"
        return try await session.respond(to: "\(request.prompt) \(mode)")
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
