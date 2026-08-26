import Foundation

final class FileShelfStore: @unchecked Sendable {
    static let defaultRetention: TimeInterval = 24 * 60 * 60
    static let largeItemThreshold: Int64 = 2 * 1_024 * 1_024 * 1_024

    private let fileManager: FileManager
    private let rootURL: URL
    private let itemsURL: URL
    private let indexURL: URL
    private let now: @Sendable () -> Date

    init(
        fileManager: FileManager = .default,
        baseURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.now = now

        if let baseURL {
            rootURL = baseURL
        } else {
            let applicationSupport = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            rootURL = applicationSupport
                .appendingPathComponent("NotchFlow", isDirectory: true)
                .appendingPathComponent("FileShelf", isDirectory: true)
        }
        itemsURL = rootURL.appendingPathComponent("Items", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("index.json")
    }

    func loadItems() throws -> [FileShelfItem] {
        try prepareStorage()
        let persisted = readIndex()
        let actualURLs = try fileManager.contentsOfDirectory(
            at: itemsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )

        var repaired = persisted.filter {
            isManaged($0.storedURL) && fileManager.fileExists(atPath: $0.storedURL.path)
        }
        let knownPaths = Set(repaired.map { $0.storedURL.standardizedFileURL.path })

        for url in actualURLs where !knownPaths.contains(url.standardizedFileURL.path) {
            repaired.append(try itemForRecoveredURL(url))
        }

        repaired.sort { $0.createdAt > $1.createdAt }
        if repaired != persisted {
            try writeIndex(repaired)
        }
        return repaired
    }

    func importItems(from sourceURLs: [URL]) throws -> FileShelfImportOutcome {
        try prepareStorage()
        var items = try loadItems()
        var importedCount = 0
        var failures: [String] = []
        var largeItems: [String] = []

        for sourceURL in sourceURLs {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

            do {
                guard sourceURL.isFileURL else {
                    throw FileShelfStoreError.unsupportedItem(sourceURL.lastPathComponent)
                }
                let values = try sourceURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey
                ])
                let isDirectory = values.isDirectory == true
                guard isDirectory || values.isRegularFile == true else {
                    throw FileShelfStoreError.unsupportedItem(sourceURL.lastPathComponent)
                }

                let byteSize = try recursiveByteSize(of: sourceURL, isDirectory: isDirectory)
                if let capacity = try? rootURL.resourceValues(
                    forKeys: [.volumeAvailableCapacityForImportantUsageKey]
                ).volumeAvailableCapacityForImportantUsage,
                   byteSize > capacity {
                    throw FileShelfStoreError.insufficientSpace(sourceURL.lastPathComponent)
                }

                let destination = uniqueDestination(
                    in: itemsURL,
                    name: sourceURL.lastPathComponent,
                    isDirectory: isDirectory
                )
                do {
                    try fileManager.copyItem(at: sourceURL, to: destination)
                } catch {
                    try? fileManager.removeItem(at: destination)
                    throw error
                }

                let item = FileShelfItem(
                    id: UUID(),
                    originalName: sourceURL.lastPathComponent,
                    displayName: destination.lastPathComponent,
                    storedURL: destination,
                    isDirectory: isDirectory,
                    byteSize: byteSize,
                    createdAt: now()
                )
                items.append(item)
                items.sort { $0.createdAt > $1.createdAt }

                do {
                    try writeIndex(items)
                } catch {
                    items.removeAll { $0.id == item.id }
                    try? fileManager.removeItem(at: destination)
                    throw error
                }

                importedCount += 1
                if byteSize > Self.largeItemThreshold {
                    largeItems.append(item.displayName)
                }
            } catch {
                failures.append("\(sourceURL.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        return FileShelfImportOutcome(
            items: items,
            importedCount: importedCount,
            failureMessages: failures,
            largeItemNames: largeItems
        )
    }

    func delete(_ item: FileShelfItem) throws -> FileShelfCleanupOutcome {
        guard isManaged(item.storedURL) else { throw FileShelfStoreError.unmanagedItem }
        var items = try loadItems()
        var failures: [String] = []
        var deletedCount = 0

        do {
            if fileManager.fileExists(atPath: item.storedURL.path) {
                try fileManager.removeItem(at: item.storedURL)
            }
            items.removeAll { $0.id == item.id }
            deletedCount = 1
        } catch {
            failures.append("\(item.displayName)：\(error.localizedDescription)")
        }
        try writeIndex(items)
        return FileShelfCleanupOutcome(
            items: items,
            deletedCount: deletedCount,
            failureMessages: failures
        )
    }

    func exportCopy(_ item: FileShelfItem, to directoryURL: URL) throws -> URL {
        guard isManaged(item.storedURL) else { throw FileShelfStoreError.unmanagedItem }
        guard fileManager.fileExists(atPath: item.storedURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw FileShelfStoreError.invalidExportDestination
        }

        let destination = uniqueDestination(
            in: directoryURL,
            name: item.displayName,
            isDirectory: item.isDirectory
        )
        try fileManager.copyItem(at: item.storedURL, to: destination)
        return destination
    }

    func clearAll() throws -> FileShelfCleanupOutcome {
        try removeItems(matching: { _ in true })
    }

    func removeExpired(
        retention: TimeInterval = FileShelfStore.defaultRetention
    ) throws -> FileShelfCleanupOutcome {
        let cutoff = now().addingTimeInterval(-retention)
        return try removeItems { $0.createdAt < cutoff }
    }

    private func removeItems(
        matching shouldDelete: (FileShelfItem) -> Bool
    ) throws -> FileShelfCleanupOutcome {
        var items = try loadItems()
        var deletedIDs: Set<UUID> = []
        var failures: [String] = []

        for item in items where shouldDelete(item) {
            guard isManaged(item.storedURL) else {
                failures.append("\(item.displayName)：\(FileShelfStoreError.unmanagedItem.localizedDescription)")
                continue
            }
            do {
                if fileManager.fileExists(atPath: item.storedURL.path) {
                    try fileManager.removeItem(at: item.storedURL)
                }
                deletedIDs.insert(item.id)
            } catch {
                failures.append("\(item.displayName)：\(error.localizedDescription)")
            }
        }

        items.removeAll { deletedIDs.contains($0.id) }
        try writeIndex(items)
        return FileShelfCleanupOutcome(
            items: items,
            deletedCount: deletedIDs.count,
            failureMessages: failures
        )
    }

    private func prepareStorage() throws {
        try fileManager.createDirectory(
            at: itemsURL,
            withIntermediateDirectories: true
        )
    }

    private func readIndex() -> [FileShelfItem] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FileShelfItem].self, from: data)) ?? []
    }

    private func writeIndex(_ items: [FileShelfItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)
        try data.write(to: indexURL, options: .atomic)
    }

    private func uniqueDestination(
        in directoryURL: URL,
        name: String,
        isDirectory: Bool
    ) -> URL {
        var candidate = directoryURL.appendingPathComponent(name, isDirectory: isDirectory)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let source = URL(fileURLWithPath: name)
        let fileExtension = isDirectory ? "" : source.pathExtension
        let baseName = fileExtension.isEmpty
            ? name
            : source.deletingPathExtension().lastPathComponent
        var index = 2
        repeat {
            let suffix = "\(baseName) (\(index))"
            let uniqueName = fileExtension.isEmpty ? suffix : "\(suffix).\(fileExtension)"
            candidate = directoryURL.appendingPathComponent(uniqueName, isDirectory: isDirectory)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private func itemForRecoveredURL(_ url: URL) throws -> FileShelfItem {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
        let isDirectory = values.isDirectory == true
        return FileShelfItem(
            id: UUID(),
            originalName: url.lastPathComponent,
            displayName: url.lastPathComponent,
            storedURL: url,
            isDirectory: isDirectory,
            byteSize: try recursiveByteSize(of: url, isDirectory: isDirectory),
            createdAt: values.creationDate ?? now()
        )
    }

    private func recursiveByteSize(of url: URL, isDirectory: Bool) throws -> Int64 {
        if !isDirectory {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: nil
        ) else { return 0 }

        var total: Int64 = 0
        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private func isManaged(_ url: URL) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent() == itemsURL.standardizedFileURL
    }
}
