import Foundation
import XCTest
@testable import NotchFlow

final class ProductivityModelTests: XCTestCase {
    func testSnapshotNormalizationRestoresModulesAndKeepsOneVisible() {
        var snapshot = ProductivitySnapshot.empty
        snapshot.moduleOrder = [.timer, .timer]
        snapshot.hiddenModules = Set(DashboardModule.allCases)

        let normalized = snapshot.normalized()

        XCTAssertEqual(Set(normalized.moduleOrder), Set(DashboardModule.allCases))
        XCTAssertEqual(normalized.moduleOrder.count, DashboardModule.allCases.count)
        XCTAssertLessThan(normalized.hiddenModules.count, DashboardModule.allCases.count)
    }

    func testTodoSortKeepsPendingDeadlineFirst() {
        let now = Date()
        let completed = ProductivityTodo(
            title: "已完成",
            deadline: now,
            isCompleted: true,
            createdAt: now
        )
        let noDeadline = ProductivityTodo(title: "无期限", createdAt: now.addingTimeInterval(20))
        let dueSoon = ProductivityTodo(title: "较早", deadline: now.addingTimeInterval(60), createdAt: now)
        let dueLater = ProductivityTodo(title: "较晚", deadline: now.addingTimeInterval(120), createdAt: now)

        let sorted = [completed, noDeadline, dueLater, dueSoon].sorted(by: ProductivitySort.todo)

        XCTAssertEqual(sorted.map(\.title), ["较早", "较晚", "无期限", "已完成"])
    }

    func testSmartTitleUsesFirstMeaningfulLineAndCapsLength() {
        XCTAssertEqual(
            ProductivityNoteTitle.derive(from: "\n## 今天的想法\n第二行"),
            "今天的想法"
        )
        XCTAssertEqual(ProductivityNoteTitle.derive(from: "  \n"), "新随笔")
        XCTAssertLessThanOrEqual(
            ProductivityNoteTitle.derive(from: String(repeating: "长", count: 100)).count,
            32
        )
    }

    func testLinkPolicyAcceptsPublicWebAndRejectsPrivateTargets() {
        XCTAssertEqual(
            ProductivityLinkPolicy.publicHTTPURL(from: "https://example.com/page#private")?.absoluteString,
            "https://example.com/page"
        )
        XCTAssertNil(ProductivityLinkPolicy.publicHTTPURL(from: "file:///tmp/test"))
        XCTAssertNil(ProductivityLinkPolicy.publicHTTPURL(from: "http://localhost:9000"))
        XCTAssertNil(ProductivityLinkPolicy.publicHTTPURL(from: "http://127.0.0.1"))
        XCTAssertNil(ProductivityLinkPolicy.publicHTTPURL(from: "http://192.168.1.10"))
        XCTAssertNil(ProductivityLinkPolicy.publicHTTPURL(from: "http://10.0.0.2"))
    }

    func testClipboardPolicyRejectsLikelySecretsAndOversizedText() {
        XCTAssertEqual(ClipboardPrivacyPolicy.recordableText("  可记录的文本  "), "可记录的文本")
        XCTAssertNil(ClipboardPrivacyPolicy.recordableText("api_key=sk-secret-token-value"))
        XCTAssertNil(ClipboardPrivacyPolicy.recordableText("-----BEGIN PRIVATE KEY-----"))
        XCTAssertNil(ClipboardPrivacyPolicy.recordableText(String(repeating: "a", count: 20_001)))
    }
}

final class ProductivityPersistenceTests: XCTestCase {
    func testFilePersistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaimonPalTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileProductivityStore(fileURL: directory.appendingPathComponent("workspace.json"))
        var snapshot = ProductivitySnapshot.empty
        snapshot.todos = [ProductivityTodo(title: "测试待办")]
        snapshot.notes = [ProductivityNote(title: "测试随笔", body: "本地内容")]

        try persistence.save(snapshot)
        let restored = try XCTUnwrap(persistence.load())

        XCTAssertEqual(restored.todos.map(\.title), ["测试待办"])
        XCTAssertEqual(restored.notes.map(\.body), ["本地内容"])
    }

    func testRecordingLibraryDropsMissingAudioAndKeepsExistingAudio() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaimonPalRecordings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = FileRecordingLibrary(directoryURL: directory)
        let existing = WorkspaceRecording(fileName: "existing.m4a", duration: 5)
        let missing = WorkspaceRecording(fileName: "missing.m4a", duration: 8)
        try Data("audio".utf8).write(to: directory.appendingPathComponent(existing.fileName))

        try library.save([missing, existing])
        let restored = try library.load()

        XCTAssertEqual(restored.map(\.id), [existing.id])
    }
}

@MainActor
final class CredentialVaultControllerTests: XCTestCase {
    func testVaultValidatesAndPersistsWithoutWritingToRealKeychain() {
        let persistence = CredentialVaultMemoryStore()
        let vault = CredentialVaultController(persistence: persistence)

        XCTAssertFalse(vault.add(label: "", account: "me", secret: "secret", kind: "账号"))
        XCTAssertTrue(vault.add(label: "测试", account: "me", secret: "secret", kind: "账号"))
        XCTAssertEqual(persistence.saved.first?.label, "测试")
        XCTAssertEqual(persistence.saved.first?.secret, "secret")

        let id = try? XCTUnwrap(vault.credentials.first?.id)
        if let id { vault.delete(id: id) }
        XCTAssertTrue(persistence.saved.isEmpty)
    }
}

private final class CredentialVaultMemoryStore: CredentialVaultPersisting {
    var saved: [VaultCredential] = []

    func load() throws -> [VaultCredential] { saved }
    func save(_ credentials: [VaultCredential]) throws { saved = credentials }
}

final class AgentCompletionRequestParserTests: XCTestCase {
    func testParsesSupportedLocalCompletionEvent() throws {
        let body = #"{"title":"编译完成","project":"Paimon Pal","taskID":"task-1"}"#
        let request = "POST /notify/codex HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"

        let event = try AgentCompletionRequestParser.parse(Data(request.utf8))

        XCTAssertEqual(event.source, .codex)
        XCTAssertEqual(event.title, "编译完成")
        XCTAssertEqual(event.project, "Paimon Pal")
        XCTAssertEqual(event.taskID, "task-1")
    }

    func testRejectsUnsupportedMethodSourceAndOversizedRequest() {
        let get = Data("GET /notify/codex HTTP/1.1\r\n\r\n".utf8)
        XCTAssertThrowsError(try AgentCompletionRequestParser.parse(get))

        let unknownBody = #"{"title":"done"}"#
        let unknown = Data("POST /notify/other HTTP/1.1\r\n\r\n\(unknownBody)".utf8)
        XCTAssertThrowsError(try AgentCompletionRequestParser.parse(unknown))

        XCTAssertThrowsError(
            try AgentCompletionRequestParser.parse(Data(repeating: 65, count: 32_769))
        )
    }

    func testFramingWaitsForCompleteBody() throws {
        let header = "POST /notify/codex HTTP/1.1\r\nContent-Length: 20\r\n\r\n"
        XCTAssertEqual(
            try AgentCompletionRequestFraming.expectedLength(in: Data(header.utf8)),
            header.utf8.count + 20
        )
        XCTAssertThrowsError(
            try AgentCompletionRequestFraming.expectedLength(
                in: Data(("POST /notify/codex HTTP/1.1\r\nContent-Length: 40000\r\n\r\n").utf8)
            )
        )
    }
}
