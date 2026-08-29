import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@main
struct LocalModelProbe {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            guard arguments.count >= 3 else {
                throw ProbeError.invalidArguments
            }

            let modelDirectory = URL(filePath: arguments[1], directoryHint: .isDirectory)
            let prompt = arguments.dropFirst(2).joined(separator: " ")
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

            let parameters = GenerateParameters(
                maxTokens: 96,
                temperature: 0,
                topP: 0.8,
                topK: 20,
                repetitionPenalty: 1.05,
                seed: nil
            )
            let session = ChatSession(
                model,
                instructions: """
                你是住在 MacBook 刘海旁边的桌面宠物，也是用户的温暖伙伴。
                你必须使用简体中文，只回复一到两句，语气自然、温柔、活泼。
                先回应用户表达的感受，再给轻量陪伴；不要把用户的经历说成自己的经历，不要反问，不要说教。
                根据情绪变化回复：疲惫时安慰，高兴或完成事情时祝贺，紧张时鼓励。每次针对用户这句话回答，不要套用固定句子。
                当输入包含最近对话记录，并且用户询问先前说过或发生过的内容时，必须依据记录准确回答，不得猜测或回避。
                不要输出思考过程、标签或角色名称。
                """,
                generateParameters: parameters
            )

            let generationStart = clock.now
            let response = try await session.respond(to: "\(prompt) /no_think")
            let generationDuration = generationStart.duration(to: clock.now)
            let cleanedResponse = ResponseSanitizer.clean(response)

            print("MODEL_LOAD_SECONDS=\(loadDuration.secondsText)")
            print("GENERATION_SECONDS=\(generationDuration.secondsText)")
            print("RESPONSE_BEGIN")
            print(cleanedResponse)
            print("RESPONSE_END")
        } catch {
            FileHandle.standardError.write(Data("MODEL_PROBE_ERROR: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

private enum ResponseSanitizer {
    static func clean(_ response: String) -> String {
        response
            .replacingOccurrences(
                of: #"(?s)<think>.*?</think>"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ProbeError: LocalizedError {
    case invalidArguments
    case missingModelDirectory(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "用法：notchflow-model-probe <模型目录> <问题>"
        case .missingModelDirectory(let path):
            "找不到模型目录：\(path)"
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
