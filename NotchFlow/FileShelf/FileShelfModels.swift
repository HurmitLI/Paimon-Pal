import Foundation

struct FileShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalName: String
    let displayName: String
    let storedURL: URL
    let isDirectory: Bool
    let byteSize: Int64
    let createdAt: Date

    var typeDescription: String {
        if isDirectory { return "文件夹" }
        let fileExtension = storedURL.pathExtension
        return fileExtension.isEmpty ? "文件" : "\(fileExtension.uppercased()) 文件"
    }
}

struct FileShelfImportOutcome: Sendable {
    let items: [FileShelfItem]
    let importedCount: Int
    let failureMessages: [String]
    let largeItemNames: [String]
}

struct FileShelfCleanupOutcome: Sendable {
    let items: [FileShelfItem]
    let deletedCount: Int
    let failureMessages: [String]
}

enum FileShelfBackgroundResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

enum FileShelfStoreError: LocalizedError, Sendable {
    case unsupportedItem(String)
    case insufficientSpace(String)
    case unmanagedItem
    case invalidExportDestination

    var errorDescription: String? {
        switch self {
        case .unsupportedItem(let name):
            "\(name) 不是可暂存的普通文件或文件夹。"
        case .insufficientSpace(let name):
            "剩余磁盘空间不足，未复制 \(name)。"
        case .unmanagedItem:
            "该文件不在 NotchFlow 暂存目录内，已拒绝删除。"
        case .invalidExportDestination:
            "选择的位置不是可用的文件夹。"
        }
    }
}
