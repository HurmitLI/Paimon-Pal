import AppKit
import XCTest
@testable import NotchFlowFeasibilityLab

@MainActor
final class FeasibilityIntegrationTests: XCTestCase {
    func testCurrentMacReturnsPowerAndDocumentsBrightnessBoundary() {
        let snapshot = SystemCapabilityProbe.read()

        XCTAssertNotNil(snapshot.power, "当前 MacBook 应能通过 IOKit 返回电源信息")
        XCTAssertNotNil(snapshot.outputVolume, "当前默认输出设备应能通过 CoreAudio 返回主音量")
        XCTAssertFalse(snapshot.brightnessConclusion.isEmpty)
    }

    func testAppleMusicIsInstalledOnCurrentMac() {
        XCTAssertNotNil(
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
        )
    }

    func testFileShelfCopiesASelectedFileIntoItsOwnStorage() throws {
        let sourceFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceFolder) }

        let source = sourceFolder.appendingPathComponent("notchflow-lab.txt")
        try Data("feasibility".utf8).write(to: source)

        let model = FileShelfLabModel()
        XCTAssertTrue(model.importFiles([source, source]))
        XCTAssertEqual(model.files.count, 2)
        let copiedURLs = model.files.map(\.storedURL)
        XCTAssertEqual(Set(copiedURLs).count, 2, "同名文件必须生成不同实验副本，不能覆盖")

        for copied in copiedURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
            XCTAssertEqual(try Data(contentsOf: copied), Data("feasibility".utf8))
        }

        model.clearLabCopies()
        XCTAssertTrue(model.files.isEmpty)
        for copied in copiedURLs {
            XCTAssertFalse(FileManager.default.fileExists(atPath: copied.path))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "清理不能删除 Finder 原文件")
    }
}
