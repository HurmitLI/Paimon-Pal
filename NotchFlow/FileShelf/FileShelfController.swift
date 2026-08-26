import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class FileShelfController: ObservableObject {
    @Published private(set) var items: [FileShelfItem] = []
    @Published private(set) var message = "将文件拖到刘海或文件架开始暂存。"
    @Published private(set) var isImporting = false
    @Published private(set) var isDropTargeted = false

    private let coordinator: ActivityCoordinator
    private let store: FileShelfStore
    private var hasStarted = false

    init(
        coordinator: ActivityCoordinator,
        store: FileShelfStore = FileShelfStore()
    ) {
        self.coordinator = coordinator
        self.store = store
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let store = store
        Task { [weak self] in
            let result = await Task.detached {
                do {
                    return FileShelfBackgroundResult.success(
                        try store.removeExpired()
                    )
                } catch {
                    return FileShelfBackgroundResult<FileShelfCleanupOutcome>.failure(
                        error.localizedDescription
                    )
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let outcome):
                items = outcome.items
                if outcome.deletedCount > 0 {
                    message = "已自动清理 \(outcome.deletedCount) 个超过 24 小时的 NotchFlow 暂存副本。"
                }
            case .failure(let errorMessage):
                message = "文件架加载失败：\(errorMessage)"
            }
        }
    }

    func chooseItems() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "暂存副本"
        panel.message = "选中内容会复制到 NotchFlow，原文件不会移动或删除。"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor [weak self] in self?.importItems(urls) }
        }
    }

    func setDropTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted {
            coordinator.beginFileReceiving()
        } else if !isImporting {
            coordinator.endFileReceiving()
        }
    }

    @discardableResult
    func importDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else {
            message = "只支持从 Finder 或其他 App 拖入普通文件和文件夹。"
            return false
        }
        message = "正在读取拖入的 (fileProviders.count) 项内容…"

        let collector = FileDropURLCollector(expectedCount: fileProviders.count) { [weak self] urls in
            guard let self else { return }
            guard !urls.isEmpty else {
                self.setDropTargeted(false)
                self.message = "未能读取拖入文件，请重新拖入或使用“选择文件…”。"
                return
            }
            self.importItems(urls)
        }

        for provider in fileProviders {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                collector.append(Self.fileURL(from: item))
            }
        }
        return true
    }

    @discardableResult
    func importItems(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, !isImporting else { return false }
        isImporting = true
        coordinator.beginFileReceiving()
        message = "正在复制 \(urls.count) 项内容到 NotchFlow 文件架…"
        let store = store

        Task { [weak self] in
            let result = await Task.detached {
                do {
                    return FileShelfBackgroundResult.success(
                        try store.importItems(from: urls)
                    )
                } catch {
                    return FileShelfBackgroundResult<FileShelfImportOutcome>.failure(
                        error.localizedDescription
                    )
                }
            }.value
            guard let self else { return }
            isImporting = false
            isDropTargeted = false
            coordinator.endFileReceiving()

            switch result {
            case .success(let outcome):
                items = outcome.items
                message = importMessage(for: outcome)
                if outcome.importedCount > 0 {
                    coordinator.showTemporaryHUD(
                        IslandActivity(
                            id: "files.imported",
                            kind: .fileDrop,
                            title: "已暂存 \(outcome.importedCount) 项",
                            detail: nil
                        ),
                        duration: .seconds(2)
                    )
                }
            case .failure(let errorMessage):
                message = "暂存失败：\(errorMessage)"
                coordinator.showTemporaryHUD(
                    IslandActivity(
                        id: "files.failed",
                        kind: .criticalSystem,
                        title: "文件暂存失败",
                        detail: errorMessage
                    ),
                    duration: .seconds(3)
                )
            }
        }
        return true
    }

    func open(_ item: FileShelfItem) {
        guard FileManager.default.fileExists(atPath: item.storedURL.path) else {
            message = "\(item.displayName) 已不在暂存目录，请重新导入。"
            reload()
            return
        }
        NSWorkspace.shared.open(item.storedURL)
        message = "已打开 \(item.displayName)。"
    }

    func reveal(_ item: FileShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.storedURL])
    }

    func sendViaAirDrop(_ selectedItems: [FileShelfItem]) {
        let existingURLs = selectedItems
            .map(\.storedURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else {
            message = "没有可发送的暂存文件。"
            return
        }
        guard let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: existingURLs)
        else {
            message = "系统当前无法使用 AirDrop；暂存副本已保留。"
            return
        }
        service.perform(withItems: existingURLs)
        message = "已打开系统 AirDrop 面板，文件会保留到您确认删除。"
    }

    func export(_ item: FileShelfItem) {
        guard FileManager.default.fileExists(atPath: item.storedURL.path) else {
            message = "\(item.displayName) 已不在暂存目录，请重新导入。"
            reload()
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "导出到这里"
        panel.message = "选择目标文件夹；NotchFlow 会复制副本，不会删除文件架内容。"
        panel.begin { [weak self] response in
            guard response == .OK, let directoryURL = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                message = "正在导出 \(item.displayName)…"
                let store = store
                let result = await Task.detached {
                    let accessed = directoryURL.startAccessingSecurityScopedResource()
                    defer { if accessed { directoryURL.stopAccessingSecurityScopedResource() } }
                    do {
                        return FileShelfBackgroundResult.success(
                            try store.exportCopy(item, to: directoryURL)
                        )
                    } catch {
                        return FileShelfBackgroundResult<URL>.failure(error.localizedDescription)
                    }
                }.value

                switch result {
                case .success(let destination):
                    message = "已导出 \(destination.lastPathComponent)；文件架副本仍保留。"
                case .failure(let errorMessage):
                    message = "导出失败：\(errorMessage)"
                }
            }
        }
    }

    func delete(_ item: FileShelfItem) {
        performCleanup { store in try store.delete(item) }
    }

    func clearAllCopies() {
        performCleanup { store in try store.clearAll() }
    }

    private func reload() {
        let store = store
        Task { [weak self] in
            let result = await Task.detached {
                do {
                    return FileShelfBackgroundResult.success(try store.loadItems())
                } catch {
                    return FileShelfBackgroundResult<[FileShelfItem]>.failure(error.localizedDescription)
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let loadedItems): items = loadedItems
            case .failure(let errorMessage): message = "文件架刷新失败：\(errorMessage)"
            }
        }
    }

    private func performCleanup(
        _ operation: @escaping @Sendable (FileShelfStore) throws -> FileShelfCleanupOutcome
    ) {
        let store = store
        Task { [weak self] in
            let result = await Task.detached {
                do {
                    return FileShelfBackgroundResult.success(try operation(store))
                } catch {
                    return FileShelfBackgroundResult<FileShelfCleanupOutcome>.failure(
                        error.localizedDescription
                    )
                }
            }.value
            guard let self else { return }
            switch result {
            case .success(let outcome):
                items = outcome.items
                if outcome.failureMessages.isEmpty {
                    message = "已删除 \(outcome.deletedCount) 个 NotchFlow 暂存副本；Finder 原文件未受影响。"
                } else {
                    message = "已删除 \(outcome.deletedCount) 个，失败 \(outcome.failureMessages.count) 个。"
                }
            case .failure(let errorMessage):
                message = "删除失败：\(errorMessage)"
            }
        }
    }

    private func importMessage(for outcome: FileShelfImportOutcome) -> String {
        var parts = ["已暂存 \(outcome.importedCount) 项，原文件未移动。"]
        if !outcome.largeItemNames.isEmpty {
            parts.append("大于 2GB：\(outcome.largeItemNames.joined(separator: "、"))。")
        }
        if !outcome.failureMessages.isEmpty {
            parts.append("失败 \(outcome.failureMessages.count) 项：\(outcome.failureMessages.joined(separator: "；"))")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String { return URL(string: string) }
        if let string = item as? NSString { return URL(string: string as String) }
        return nil
    }
}

private final class FileDropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var urls: [URL] = []
    private let completion: @MainActor ([URL]) -> Void

    init(expectedCount: Int, completion: @escaping @MainActor ([URL]) -> Void) {
        remaining = expectedCount
        self.completion = completion
    }

    func append(_ url: URL?) {
        let completedURLs: [URL]? = lock.withLock {
            if let url { urls.append(url) }
            remaining -= 1
            return remaining == 0 ? urls : nil
        }
        guard let completedURLs else { return }
        Task { @MainActor [completion] in completion(completedURLs) }
    }
}
