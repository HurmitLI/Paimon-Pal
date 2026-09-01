import AppKit
import Combine
import Foundation
import UserNotifications

protocol ProductivityPersisting {
    func load() throws -> ProductivitySnapshot?
    func save(_ snapshot: ProductivitySnapshot) throws
}

struct FileProductivityStore: ProductivityPersisting {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.fileURL = root
            .appendingPathComponent("Paimon Pal", isDirectory: true)
            .appendingPathComponent("productivity", isDirectory: true)
            .appendingPathComponent("workspace-v1.json")
    }

    func load() throws -> ProductivitySnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ProductivitySnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }

    func save(_ snapshot: ProductivitySnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

@MainActor
final class ProductivityStore: ObservableObject {
    @Published private(set) var moduleOrder: [DashboardModule]
    @Published private(set) var hiddenModules: Set<DashboardModule>
    @Published private(set) var todos: [ProductivityTodo]
    @Published private(set) var notes: [ProductivityNote]
    @Published private(set) var links: [ProductivityLink]
    @Published private(set) var clipboardEntries: [ProductivityClipboardEntry]
    @Published private(set) var clipboardHistoryEnabled: Bool
    @Published private(set) var statusMessage = "所有数据只保存在本机。"

    private let persistence: ProductivityPersisting
    private let pasteboard: NSPasteboard
    private var clipboardTask: Task<Void, Never>?
    private var lastPasteboardChangeCount = 0

    init(
        persistence: ProductivityPersisting = FileProductivityStore(),
        pasteboard: NSPasteboard = .general
    ) {
        self.persistence = persistence
        self.pasteboard = pasteboard

        let snapshot: ProductivitySnapshot
        do {
            snapshot = try persistence.load()?.normalized() ?? .empty
        } catch {
            snapshot = .empty
            statusMessage = "工作区数据无法读取，已使用空白工作区。"
        }
        moduleOrder = snapshot.moduleOrder
        hiddenModules = snapshot.hiddenModules
        todos = snapshot.todos
        notes = snapshot.notes
        links = snapshot.links
        clipboardEntries = snapshot.clipboardEntries
        clipboardHistoryEnabled = snapshot.clipboardHistoryEnabled
        lastPasteboardChangeCount = pasteboard.changeCount

        if clipboardHistoryEnabled {
            startClipboardMonitoring()
        }
    }

    deinit {
        clipboardTask?.cancel()
    }

    var visibleModules: [DashboardModule] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    var pendingTodos: [ProductivityTodo] {
        todos.filter { !$0.isCompleted }.sorted(by: ProductivitySort.todo)
    }

    var activeNotes: [ProductivityNote] {
        notes.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func setModule(_ module: DashboardModule, hidden: Bool) {
        var next = hiddenModules
        if hidden {
            guard visibleModules.count > 1 else {
                statusMessage = "工作台至少保留一个模块。"
                return
            }
            next.insert(module)
        } else {
            next.remove(module)
        }
        hiddenModules = next
        persist(message: hidden ? "已隐藏“\(module.title)”。" : "已恢复“\(module.title)”。")
    }

    func moveModule(_ module: DashboardModule, offset: Int) {
        guard let index = moduleOrder.firstIndex(of: module) else { return }
        let destination = min(max(index + offset, 0), moduleOrder.count - 1)
        guard index != destination else { return }
        var next = moduleOrder
        next.remove(at: index)
        next.insert(module, at: destination)
        moduleOrder = next
        persist(message: "工作台顺序已保存。")
    }

    @discardableResult
    func addTodo(title: String, category: String = "今天", deadline: Date? = nil) -> ProductivityTodo? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let todo = ProductivityTodo(
            title: String(normalizedTitle.prefix(160)),
            category: normalizedCategory.isEmpty ? "今天" : String(normalizedCategory.prefix(24)),
            deadline: deadline
        )
        todos.append(todo)
        todos.sort(by: ProductivitySort.todo)
        persist(message: "待办已保存。")
        scheduleReminder(for: todo)
        return todo
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isCompleted.toggle()
        let todo = todos[index]
        todos.sort(by: ProductivitySort.todo)
        persist(message: todo.isCompleted ? "待办已完成。" : "待办已恢复。")
        if todo.isCompleted {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [reminderIdentifier(for: id)]
            )
        } else {
            scheduleReminder(for: todo)
        }
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [reminderIdentifier(for: id)]
        )
        persist(message: "待办已删除。")
    }

    @discardableResult
    func createNote(body: String = "") -> ProductivityNote {
        let note = ProductivityNote(
            title: ProductivityNoteTitle.derive(from: body),
            body: body
        )
        notes.insert(note, at: 0)
        persist(message: "随笔已创建。")
        return note
    }

    func updateNote(id: UUID, title: String, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notes[index].title = explicitTitle.isEmpty
            ? ProductivityNoteTitle.derive(from: body)
            : String(explicitTitle.prefix(64))
        notes[index].body = String(body.prefix(100_000))
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        persist(message: "随笔已保存。")
    }

    func archiveNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isArchived = true
        notes[index].updatedAt = Date()
        persist(message: "随笔已归档。")
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        persist(message: "随笔已删除。")
    }

    @discardableResult
    func addLink(rawURL: String, title: String = "") -> ProductivityLink? {
        guard let url = ProductivityLinkPolicy.publicHTTPURL(from: rawURL),
              !links.contains(where: { $0.url == url })
        else {
            statusMessage = "只能保存公开的 HTTP/HTTPS 链接，且不能重复。"
            return nil
        }
        let explicitTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = url.host() ?? url.absoluteString
        let link = ProductivityLink(
            url: url,
            title: explicitTitle.isEmpty ? fallbackTitle : String(explicitTitle.prefix(100))
        )
        links.insert(link, at: 0)
        persist(message: "链接已保存。")
        return link
    }

    func renameLink(id: UUID, title: String) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        links[index].title = String(normalized.prefix(100))
        persist(message: "链接标题已更新。")
    }

    func deleteLink(id: UUID) {
        links.removeAll { $0.id == id }
        persist(message: "链接已删除。")
    }

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        clipboardHistoryEnabled = enabled
        lastPasteboardChangeCount = pasteboard.changeCount
        if enabled {
            startClipboardMonitoring()
            statusMessage = "剪贴板历史已开启；开启前的内容不会被读取。"
        } else {
            clipboardTask?.cancel()
            clipboardTask = nil
            statusMessage = "剪贴板历史已关闭。"
        }
        persist()
    }

    func clearClipboardHistory() {
        clipboardEntries.removeAll()
        persist(message: "剪贴板历史已清空。")
    }

    func copyToPasteboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastPasteboardChangeCount = pasteboard.changeCount
        statusMessage = "已复制。"
    }

    private func startClipboardMonitoring() {
        guard clipboardTask == nil else { return }
        clipboardTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                capturePasteboardIfNeeded()
            }
        }
    }

    private func capturePasteboardIfNeeded() {
        guard clipboardHistoryEnabled,
              pasteboard.changeCount != lastPasteboardChangeCount
        else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        guard let rawValue = pasteboard.string(forType: .string),
              let text = ClipboardPrivacyPolicy.recordableText(rawValue),
              clipboardEntries.first?.text != text
        else { return }
        clipboardEntries.insert(ProductivityClipboardEntry(text: text), at: 0)
        if clipboardEntries.count > 80 {
            clipboardEntries.removeLast(clipboardEntries.count - 80)
        }
        persist(message: "已记录新的剪贴板文本。")
    }

    private func persist(message: String? = nil) {
        do {
            try persistence.save(snapshot.normalized())
            if let message { statusMessage = message }
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private var snapshot: ProductivitySnapshot {
        ProductivitySnapshot(
            moduleOrder: moduleOrder,
            hiddenModules: hiddenModules,
            todos: todos,
            notes: notes,
            links: links,
            clipboardHistoryEnabled: clipboardHistoryEnabled,
            clipboardEntries: clipboardEntries
        )
    }

    private func scheduleReminder(for todo: ProductivityTodo) {
        guard let deadline = todo.deadline else { return }
        let reminderDate = deadline.addingTimeInterval(-3_600)
        guard reminderDate > Date() else { return }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard [.authorized, .provisional].contains(settings.authorizationStatus) else { return }
            let content = UNMutableNotificationContent()
            content.title = "派蒙提醒你"
            content.body = "“\(todo.title)”还有一小时截止。"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: reminderDate
                ),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: reminderIdentifier(for: todo.id),
                content: content,
                trigger: trigger
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func reminderIdentifier(for id: UUID) -> String {
        "PaimonPal.todo.\(id.uuidString)"
    }
}
