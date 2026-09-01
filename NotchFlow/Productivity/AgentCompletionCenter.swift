import Foundation
import Network

enum AgentCompletionSource: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case gpt

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .gpt: "GPT"
        }
    }
}

struct AgentCompletionEvent: Codable, Equatable, Sendable {
    let source: AgentCompletionSource
    let title: String
    let project: String?
    let taskID: String?
    let receivedAt: Date

    init(
        source: AgentCompletionSource,
        title: String,
        project: String? = nil,
        taskID: String? = nil,
        receivedAt: Date = Date()
    ) {
        self.source = source
        self.title = title
        self.project = project
        self.taskID = taskID
        self.receivedAt = receivedAt
    }
}

enum AgentCompletionRequestError: Error, Equatable {
    case malformedRequest
    case unsupportedMethod
    case unsupportedSource
    case invalidBody
}

enum AgentCompletionRequestParser {
    private struct Payload: Decodable {
        let title: String?
        let project: String?
        let taskID: String?

        enum CodingKeys: String, CodingKey {
            case title
            case project
            case taskID
            case snakeTaskID = "task_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            project = try container.decodeIfPresent(String.self, forKey: .project)
            taskID = try container.decodeIfPresent(String.self, forKey: .taskID)
                ?? container.decodeIfPresent(String.self, forKey: .snakeTaskID)
        }
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> AgentCompletionEvent {
        guard data.count <= 32_768,
              let separator = data.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8),
              let requestLine = headerText.split(separator: "\r\n").first
        else { throw AgentCompletionRequestError.malformedRequest }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { throw AgentCompletionRequestError.malformedRequest }
        guard parts[0] == "POST" else { throw AgentCompletionRequestError.unsupportedMethod }

        let path = String(parts[1])
        guard path.hasPrefix("/notify/"),
              let source = AgentCompletionSource(rawValue: String(path.dropFirst("/notify/".count)))
        else { throw AgentCompletionRequestError.unsupportedSource }

        let body = data[separator.upperBound...]
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body) else {
            throw AgentCompletionRequestError.invalidBody
        }
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { throw AgentCompletionRequestError.invalidBody }
        return AgentCompletionEvent(
            source: source,
            title: String(title.prefix(120)),
            project: payload.project.map { String($0.prefix(120)) },
            taskID: payload.taskID.map { String($0.prefix(160)) },
            receivedAt: now
        )
    }
}

enum AgentCompletionRequestFraming {
    static func expectedLength(in data: Data) throws -> Int? {
        guard data.count <= 32_768 else { throw AgentCompletionRequestError.malformedRequest }
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headers = String(data: data[..<separator.lowerBound], encoding: .utf8) else {
            throw AgentCompletionRequestError.malformedRequest
        }
        let contentLength = headers
            .split(separator: "\r\n")
            .dropFirst()
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
        guard let contentLength else { return nil }
        guard contentLength >= 0 else { throw AgentCompletionRequestError.malformedRequest }
        let expected = separator.upperBound + contentLength
        guard expected <= 32_768 else { throw AgentCompletionRequestError.malformedRequest }
        return expected
    }
}

@MainActor
final class AgentCompletionCenter: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var statusText = "AI 完成提醒尚未启动"
    @Published private(set) var lastEvent: AgentCompletionEvent?

    var onEvent: ((AgentCompletionEvent) -> Void)?

    private var listener: NWListener?
    private nonisolated let queue = DispatchQueue(label: "PaimonPal.AgentCompletionServer")

    func start(port: UInt16 = 43_821) {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: port) else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        isListening = true
                        statusText = "正在监听 127.0.0.1:\(port.rawValue)"
                    case .failed(let error):
                        isListening = false
                        statusText = "AI 完成提醒启动失败：\(error.localizedDescription)"
                        listener.cancel()
                        self.listener = nil
                    case .cancelled:
                        isListening = false
                        statusText = "AI 完成提醒已停止"
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        } catch {
            statusText = "AI 完成提醒启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    private nonisolated func receive(on connection: NWConnection, accumulated: Data) {
        let remaining = max(1, 32_768 - accumulated.count)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: remaining
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var request = accumulated
            if let data { request.append(data) }

            do {
                if let expected = try AgentCompletionRequestFraming.expectedLength(in: request),
                   request.count < expected,
                   !isComplete,
                   error == nil {
                    receive(on: connection, accumulated: request)
                    return
                }
            } catch {
                respond(.failure(.malformedRequest), on: connection)
                return
            }

            let result: Result<AgentCompletionEvent, AgentCompletionRequestError>
            if !request.isEmpty {
                do {
                    result = .success(try AgentCompletionRequestParser.parse(request))
                } catch let error as AgentCompletionRequestError {
                    result = .failure(error)
                } catch {
                    result = .failure(.malformedRequest)
                }
            } else {
                result = .failure(.malformedRequest)
            }

            respond(result, on: connection)
        }
    }

    private nonisolated func respond(
        _ result: Result<AgentCompletionEvent, AgentCompletionRequestError>,
        on connection: NWConnection
    ) {
        let response: String
            switch result {
            case .success(let event):
                response = "HTTP/1.1 202 Accepted\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                Task { @MainActor [weak self] in self?.receive(event) }
            case .failure(let error):
                let status = error == .unsupportedSource ? "404 Not Found" : "400 Bad Request"
                response = "HTTP/1.1 \(status)\r\nContent-Length: 5\r\nConnection: close\r\n\r\nERROR"
            }
            connection.send(
                content: Data(response.utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )
    }

    private func receive(_ event: AgentCompletionEvent) {
        lastEvent = event
        statusText = "最近完成：\(event.source.displayName) · \(event.title)"
        onEvent?(event)
    }
}
