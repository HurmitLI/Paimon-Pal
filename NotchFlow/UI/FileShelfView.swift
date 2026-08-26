import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    @ObservedObject var shelf: FileShelfController

    @State private var pendingDelete: FileShelfItem?
    @State private var isClearConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            HStack {
                Text("暂存副本 \(shelf.items.count) 项")
                    .font(.headline)
                Spacer()
                Button("AirDrop 全部") {
                    shelf.sendViaAirDrop(shelf.items)
                }
                .disabled(shelf.items.isEmpty)
                Button("清理全部", role: .destructive) {
                    isClearConfirmationPresented = true
                }
                .disabled(shelf.items.isEmpty)
            }

            if shelf.items.isEmpty {
                ContentUnavailableView(
                    "还没有暂存文件",
                    systemImage: "tray",
                    description: Text("拖入文件或文件夹，NotchFlow 只会复制副本。")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(shelf.items) { item in
                            fileRow(item)
                        }
                    }
                }
            }

            Text(shelf.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .confirmationDialog(
            "只删除 NotchFlow 创建的暂存副本？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除 \(shelf.items.count) 个暂存副本", role: .destructive) {
                shelf.clearAllCopies()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Finder 中的原文件不会被删除。")
        }
        .alert(
            "删除暂存副本？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { item in
            Button("仅删除 NotchFlow 副本", role: .destructive) {
                shelf.delete(item)
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { item in
            Text("\(item.displayName) 的 Finder 原文件不会被删除。")
        }
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: shelf.isImporting ? "arrow.down.doc.fill" : "plus.square.dashed")
                .font(.title2)
                .foregroundStyle(shelf.isDropTargeted ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.isImporting ? "正在复制到文件架…" : "拖入文件或文件夹")
                    .font(.headline)
                Text("保留 24 小时；原文件不会移动或删除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("选择文件…") { shelf.chooseItems() }
                .buttonStyle(.borderedProminent)
                .disabled(shelf.isImporting)
        }
        .padding(14)
        .background(
            shelf.isDropTargeted ? .blue.opacity(0.12) : .secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    shelf.isDropTargeted ? .blue : .secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: Binding(
                get: { shelf.isDropTargeted },
                set: { shelf.setDropTargeted($0) }
            ),
            perform: shelf.importDroppedProviders
        )
    }

    private func fileRow(_ item: FileShelfItem) -> some View {
        HStack(spacing: 10) {
            FileShelfThumbnailView(item: item)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("\(item.typeDescription) · \(sizeText(item.byteSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("暂存于 \(createdAtText(item.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button("导出…") {
                shelf.export(item)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("选择文件夹并导出副本；也可以直接拖动整行到 Finder")

            Button {
                shelf.sendViaAirDrop([item])
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .accessibilityHidden(true)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("AirDrop"))
            .help("AirDrop")

            Button {
                pendingDelete = item
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除 NotchFlow 暂存副本")
        }
        .padding(10)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { shelf.open(item) }
        .onDrag {
            NSItemProvider(contentsOf: item.storedURL) ?? NSItemProvider()
        }
        .help("单击打开；拖到 Finder 可导出副本")
        .contextMenu {
            Button("打开") { shelf.open(item) }
            Button("在 Finder 中显示") { shelf.reveal(item) }
            Button("导出副本…") { shelf.export(item) }
            Button("AirDrop") { shelf.sendViaAirDrop([item]) }
            Divider()
            Button("删除暂存副本", role: .destructive) { pendingDelete = item }
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func createdAtText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FileShelfThumbnailView: View {
    let item: FileShelfItem

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.storedURL.path))
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            }
        }
        .frame(width: 38, height: 38)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: item.storedURL) {
            thumbnail = await loadThumbnail()
        }
        .accessibilityHidden(true)
    }

    private func loadThumbnail() async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.storedURL,
            size: CGSize(width: 76, height: 76),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
            .nsImage
    }
}
