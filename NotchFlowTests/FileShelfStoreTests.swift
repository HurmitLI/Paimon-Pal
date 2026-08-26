import AppKit
import Foundation
import XCTest
@testable import NotchFlow

final class FileShelfStoreTests: XCTestCase {
    func testFinderFileURLDataDecodesForDropImport() throws {
        let source = URL(fileURLWithPath: "/tmp/notchflow-drop-test.txt")
        let representation = try XCTUnwrap(source.dataRepresentation)

        XCTAssertEqual(FileShelfController.fileURL(from: representation as NSData), source)
    }

    @MainActor
    func testFinderItemProviderImportsThroughControllerAndKeepsSource() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = fixture.sources.appendingPathComponent("finder-drop.txt")
        try Data("finder-drop".utf8).write(to: source)
        let store = FileShelfStore(baseURL: fixture.shelf)
        let controller = FileShelfController(
            coordinator: ActivityCoordinator(),
            store: store
        )
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))

        XCTAssertTrue(controller.importDroppedProviders([provider]))
        for _ in 0..<100 where controller.items.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }

        let item = try XCTUnwrap(controller.items.first)
        XCTAssertEqual(try Data(contentsOf: item.storedURL), Data("finder-drop".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testImportCopiesDuplicatesWithoutOverwritingAndKeepsSource() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = fixture.sources.appendingPathComponent("report.txt")
        try Data("notchflow".utf8).write(to: source)
        let store = FileShelfStore(baseURL: fixture.shelf)

        let outcome = try store.importItems(from: [source, source])

        XCTAssertEqual(outcome.importedCount, 2)
        XCTAssertTrue(outcome.failureMessages.isEmpty)
        XCTAssertEqual(outcome.items.count, 2)
        XCTAssertEqual(Set(outcome.items.map(\.storedURL)).count, 2)
        XCTAssertEqual(Set(outcome.items.map(\.displayName)), ["report.txt", "report (2).txt"])
        for item in outcome.items {
            XCTAssertEqual(try Data(contentsOf: item.storedURL), Data("notchflow".utf8))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let deletion = try store.delete(outcome.items[0])
        XCTAssertEqual(deletion.deletedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testFolderImportCopiesNestedContent() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let sourceFolder = fixture.sources.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try Data("nested".utf8).write(
            to: sourceFolder.appendingPathComponent("note.md")
        )
        let store = FileShelfStore(baseURL: fixture.shelf)

        let outcome = try store.importItems(from: [sourceFolder])

        XCTAssertEqual(outcome.importedCount, 1)
        let item = try XCTUnwrap(outcome.items.first)
        XCTAssertTrue(item.isDirectory)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: item.storedURL.appendingPathComponent("note.md").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceFolder.path))
    }

    func testExportCopiesManagedItemWithoutRemovingShelfCopy() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = fixture.sources.appendingPathComponent("export.txt")
        let exports = fixture.root.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try Data("exported".utf8).write(to: source)
        let store = FileShelfStore(baseURL: fixture.shelf)
        let imported = try store.importItems(from: [source])
        let item = try XCTUnwrap(imported.items.first)

        let firstExport = try store.exportCopy(item, to: exports)
        let secondExport = try store.exportCopy(item, to: exports)

        XCTAssertEqual(firstExport.lastPathComponent, "export.txt")
        XCTAssertEqual(secondExport.lastPathComponent, "export (2).txt")
        XCTAssertEqual(try Data(contentsOf: firstExport), Data("exported".utf8))
        XCTAssertEqual(try Data(contentsOf: secondExport), Data("exported".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testLoadRepairsMissingIndexEntriesAndRecoversManagedOrphans() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = fixture.sources.appendingPathComponent("indexed.txt")
        try Data("index".utf8).write(to: source)
        let store = FileShelfStore(baseURL: fixture.shelf)
        let imported = try store.importItems(from: [source])
        try FileManager.default.removeItem(at: try XCTUnwrap(imported.items.first).storedURL)

        XCTAssertTrue(try store.loadItems().isEmpty)

        let orphan = fixture.shelf
            .appendingPathComponent("Items", isDirectory: true)
            .appendingPathComponent("orphan.txt")
        try Data("orphan".utf8).write(to: orphan)
        let repaired = try store.loadItems()

        XCTAssertEqual(repaired.count, 1)
        XCTAssertEqual(repaired.first?.displayName, "orphan.txt")
    }

    func testExpiredCleanupOnlyDeletesManagedCopy() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let source = fixture.sources.appendingPathComponent("keep-original.txt")
        try Data("safe".utf8).write(to: source)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let oldStore = FileShelfStore(baseURL: fixture.shelf, now: { oldDate })
        let imported = try oldStore.importItems(from: [source])
        let storedURL = try XCTUnwrap(imported.items.first?.storedURL)

        let futureStore = FileShelfStore(
            baseURL: fixture.shelf,
            now: { oldDate.addingTimeInterval(FileShelfStore.defaultRetention + 1) }
        )
        let cleanup = try futureStore.removeExpired()

        XCTAssertEqual(cleanup.deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMissingSourceReportsFailureWithoutCreatingPhantomItem() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let missingSource = fixture.sources.appendingPathComponent("missing.txt")
        let store = FileShelfStore(baseURL: fixture.shelf)

        let outcome = try store.importItems(from: [missingSource])

        XCTAssertEqual(outcome.importedCount, 0)
        XCTAssertEqual(outcome.failureMessages.count, 1)
        XCTAssertTrue(outcome.items.isEmpty)
        XCTAssertTrue(try store.loadItems().isEmpty)
    }

    private func makeFixture() throws -> (root: URL, sources: URL, shelf: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        let shelf = root.appendingPathComponent("Shelf", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        return (root, sources, shelf)
    }
}
