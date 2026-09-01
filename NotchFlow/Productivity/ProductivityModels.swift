import Foundation

enum WorkspaceSection: String, CaseIterable, Codable, Identifiable {
    case dashboard
    case todos
    case notes
    case links
    case clipboard
    case recordings
    case mirror
    case vault

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "工作台"
        case .todos: "待办"
        case .notes: "随笔记"
        case .links: "链接"
        case .clipboard: "剪贴板"
        case .recordings: "录音"
        case .mirror: "镜子"
        case .vault: "保险箱"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2.fill"
        case .todos: "checklist"
        case .notes: "note.text"
        case .links: "link"
        case .clipboard: "clipboard"
        case .recordings: "waveform"
        case .mirror: "camera.fill"
        case .vault: "lock.shield.fill"
        }
    }
}

enum DashboardModule: String, CaseIterable, Codable, Identifiable {
    case music
    case timer
    case system
    case files
    case todos
    case notes
    case launcher
    case agent
    case recorder
    case mirror

    var id: Self { self }

    var title: String {
        switch self {
        case .music: "正在播放"
        case .timer: "专注计时"
        case .system: "系统状态"
        case .files: "文件架"
        case .todos: "待办事项"
        case .notes: "随笔记"
        case .launcher: "快捷启动"
        case .agent: "AI 任务"
        case .recorder: "快速录音"
        case .mirror: "镜子"
        }
    }

    var systemImage: String {
        switch self {
        case .music: "music.note"
        case .timer: "timer"
        case .system: "gauge.with.dots.needle.67percent"
        case .files: "tray.full"
        case .todos: "checkmark.circle"
        case .notes: "note.text"
        case .launcher: "square.grid.3x3.fill"
        case .agent: "sparkles.rectangle.stack"
        case .recorder: "waveform.circle.fill"
        case .mirror: "camera.circle.fill"
        }
    }
}

struct ProductivityTodo: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var category: String
    var deadline: Date?
    var isCompleted: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        category: String = "今天",
        deadline: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

struct ProductivityNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProductivityLink: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    let createdAt: Date

    init(id: UUID = UUID(), url: URL, title: String, createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.createdAt = createdAt
    }

    var host: String { url.host() ?? url.absoluteString }
}

struct ProductivityClipboardEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

struct ProductivitySnapshot: Codable, Equatable, Sendable {
    var moduleOrder: [DashboardModule]
    var hiddenModules: Set<DashboardModule>
    var todos: [ProductivityTodo]
    var notes: [ProductivityNote]
    var links: [ProductivityLink]
    var clipboardHistoryEnabled: Bool
    var clipboardEntries: [ProductivityClipboardEntry]

    static let empty = ProductivitySnapshot(
        moduleOrder: DashboardModule.allCases,
        hiddenModules: [],
        todos: [],
        notes: [],
        links: [],
        clipboardHistoryEnabled: false,
        clipboardEntries: []
    )

    func normalized() -> ProductivitySnapshot {
        var uniqueOrder: [DashboardModule] = []
        for module in moduleOrder where !uniqueOrder.contains(module) {
            uniqueOrder.append(module)
        }
        for module in DashboardModule.allCases where !uniqueOrder.contains(module) {
            uniqueOrder.append(module)
        }

        var result = self
        result.moduleOrder = uniqueOrder
        result.hiddenModules = hiddenModules.intersection(Set(DashboardModule.allCases))
        if result.hiddenModules.count == DashboardModule.allCases.count,
           let first = result.moduleOrder.first {
            result.hiddenModules.remove(first)
        }
        result.todos = todos
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted(by: ProductivitySort.todo)
        result.notes = notes.sorted { $0.updatedAt > $1.updatedAt }
        result.links = Array(links.prefix(500))
        result.clipboardEntries = Array(clipboardEntries.prefix(80))
        return result
    }
}

enum ProductivitySort {
    static func todo(_ lhs: ProductivityTodo, _ rhs: ProductivityTodo) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        switch (lhs.deadline, rhs.deadline) {
        case let (.some(left), .some(right)):
            if left != right { return left < right }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        return lhs.createdAt > rhs.createdAt
    }
}

enum ProductivityNoteTitle {
    static func derive(from body: String) -> String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "新随笔"
        let cleaned = firstLine
            .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(32)).isEmpty ? "新随笔" : String(cleaned.prefix(32))
    }
}

enum ProductivityLinkPolicy {
    static func publicHTTPURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              isPublicHost(host)
        else { return nil }
        components.fragment = nil
        return components.url
    }

    static func isPublicHost(_ host: String) -> Bool {
        let blockedNames = ["localhost", "localhost.localdomain"]
        guard !blockedNames.contains(host),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal")
        else { return false }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            let a = octets[0]
            let b = octets[1]
            if a == 10 || a == 127 || a == 0 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
        }
        if host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80") {
            return false
        }
        return true
    }
}

enum ClipboardPrivacyPolicy {
    private static let sensitiveMarkers = [
        "BEGIN PRIVATE KEY",
        "BEGIN OPENSSH PRIVATE KEY",
        "password=",
        "passwd=",
        "api_key=",
        "authorization: bearer",
        "ghp_",
        "sk-proj-"
    ]

    static func recordableText(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 10_000 else { return nil }
        let lowercased = value.lowercased()
        guard !sensitiveMarkers.contains(where: { lowercased.contains($0.lowercased()) }) else {
            return nil
        }
        return value
    }
}
