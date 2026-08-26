import AppKit
import Combine
import Foundation
import SwiftUI

struct StoredLabFile: Identifiable, Hashable {
    let id = UUID()
    let originalName: String
    let storedURL: URL
}

@MainActor
final class FileShelfLabModel: ObservableObject {
    @Published private(set) var files: [StoredLabFile] = []
    @Published private(set) var lastMessage = "尚未导入文件"

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.importFiles(panel.urls)
        }
    }

    @discardableResult
    func importFiles(_ urls: [URL]) -> Bool {
        var successes = 0
        var failures: [String] = []

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let destination = try destinationURL(for: url)
                try FileManager.default.copyItem(at: url, to: destination)
                files.append(StoredLabFile(originalName: url.lastPathComponent, storedURL: destination))
                successes += 1
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            lastMessage = "成功复制 \(successes) 个文件到 App 沙盒目录"
        } else {
            lastMessage = "成功 \(successes) 个；失败 \(failures.count) 个：\(failures.joined(separator: "；"))"
        }
        return successes > 0
    }

    func sendViaAirDrop(_ file: StoredLabFile) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            lastMessage = "系统当前没有提供 AirDrop 分享服务"
            return
        }
        service.perform(withItems: [file.storedURL])
        lastMessage = "已调用系统 AirDrop 分享面板；是否发送由您在系统面板中决定"
    }

    func reveal(_ file: StoredLabFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.storedURL])
    }

    func clearLabCopies() {
        let allowedFolder: URL
        do {
            allowedFolder = try storageFolderURL().standardizedFileURL
        } catch {
            lastMessage = "无法定位实验目录：\(error.localizedDescription)"
            return
        }

        var deleted = 0
        var failed = 0
        for file in files {
            let candidate = file.storedURL.standardizedFileURL
            guard candidate.deletingLastPathComponent() == allowedFolder else {
                failed += 1
                continue
            }
            do {
                try FileManager.default.removeItem(at: candidate)
                deleted += 1
            } catch {
                failed += 1
            }
        }
        files.removeAll { !FileManager.default.fileExists(atPath: $0.storedURL.path) }
        lastMessage = failed == 0
            ? "已删除 \(deleted) 个实验副本；Finder 原文件不会被删除"
            : "已删除 \(deleted) 个实验副本，\(failed) 个未删除"
    }

    private func destinationURL(for source: URL) throws -> URL {
        try storageFolderURL()
            .appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
    }

    private func storageFolderURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("NotchFlowFeasibilityLab/TestShelf", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

struct FileShelfLabView: View {
    @StateObject private var model = FileShelfLabModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("把文件拖到这里")
                    .font(.headline)
                Spacer()
                Button("选择文件") { model.chooseFiles() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(isDropTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .dropDestination(for: URL.self, action: { urls, _ in
                model.importFiles(urls)
            }, isTargeted: { isDropTargeted = $0 })

            ForEach(model.files) { file in
                HStack {
                    Image(systemName: "doc")
                    Text(file.originalName).lineLimit(1)
                    Spacer()
                    Button("在 Finder 显示") { model.reveal(file) }
                    Button("AirDrop") { model.sendViaAirDrop(file) }
                }
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .draggable(file.storedURL)
            }

            Text("提示：列表中的文件可直接拖回 Finder。")
                .foregroundStyle(.secondary)
            Button("清理实验副本", role: .destructive) {
                model.clearLabCopies()
            }
            .disabled(model.files.isEmpty)
            Text("实验结果：\(model.lastMessage)")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}
