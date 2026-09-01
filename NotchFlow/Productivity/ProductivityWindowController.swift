import AppKit
import SwiftUI

@MainActor
private final class ProductivityWindowModel: ObservableObject {
    @Published var selection: WorkspaceSection = .dashboard
}

@MainActor
final class ProductivityWindowController {
    private let window: NSWindow
    private let model = ProductivityWindowModel()

    init(
        store: ProductivityStore,
        launcher: QuickLauncherController,
        agentCenter: AgentCompletionCenter,
        music: MusicController,
        fileShelf: FileShelfController,
        systemStatus: SystemStatusController,
        timer: TimerController,
        recording: RecordingController,
        mirror: MirrorCameraController,
        vault: CredentialVaultController,
        onOpenUtility: @escaping (UtilitySection) -> Void
    ) {
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paimon Pal 工作台"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 820, height: 560)
        window.setFrameAutosaveName("PaimonPal.ProductivityWindow")

        let root = ProductivityRootView(
            model: model,
            store: store,
            launcher: launcher,
            agentCenter: agentCenter,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer,
            recording: recording,
            mirror: mirror,
            vault: vault,
            onOpenUtility: onOpenUtility
        )
        let hostingView = NSHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    func show(section: WorkspaceSection = .dashboard) {
        model.selection = section
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ProductivityRootView: View {
    @ObservedObject var model: ProductivityWindowModel
    @ObservedObject var store: ProductivityStore
    @ObservedObject var launcher: QuickLauncherController
    @ObservedObject var agentCenter: AgentCompletionCenter
    @ObservedObject var music: MusicController
    @ObservedObject var fileShelf: FileShelfController
    @ObservedObject var systemStatus: SystemStatusController
    @ObservedObject var timer: TimerController
    @ObservedObject var recording: RecordingController
    @ObservedObject var mirror: MirrorCameraController
    @ObservedObject var vault: CredentialVaultController
    let onOpenUtility: (UtilitySection) -> Void

    var body: some View {
        NavigationSplitView {
            List(WorkspaceSection.allCases, selection: $model.selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 175, max: 220)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Paimon Pal", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                    Text("本地工作台")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        } detail: {
            Group {
                switch model.selection {
                case .dashboard:
                    DashboardView(
                        model: model,
                        store: store,
                        launcher: launcher,
                        agentCenter: agentCenter,
                        music: music,
                        fileShelf: fileShelf,
                        systemStatus: systemStatus,
                        timer: timer,
                        recording: recording,
                        mirror: mirror,
                        onOpenUtility: onOpenUtility
                    )
                case .todos:
                    ProductivityTodosView(store: store)
                case .notes:
                    ProductivityNotesView(store: store)
                case .links:
                    ProductivityLinksView(store: store)
                case .clipboard:
                    ProductivityClipboardView(store: store)
                case .recordings:
                    ProductivityRecordingsView(recording: recording)
                case .mirror:
                    ProductivityMirrorView(mirror: mirror)
                case .vault:
                    ProductivityVaultView(vault: vault, store: store)
                }
            }
            .navigationTitle(model.selection.title)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text(store.statusMessage)
                        .lineLimit(1)
                    Spacer()
                    Text("仅本机")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: ProductivityWindowModel
    @ObservedObject var store: ProductivityStore
    @ObservedObject var launcher: QuickLauncherController
    @ObservedObject var agentCenter: AgentCompletionCenter
    @ObservedObject var music: MusicController
    @ObservedObject var fileShelf: FileShelfController
    @ObservedObject var systemStatus: SystemStatusController
    @ObservedObject var timer: TimerController
    @ObservedObject var recording: RecordingController
    @ObservedObject var mirror: MirrorCameraController
    let onOpenUtility: (UtilitySection) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今天想先做什么？")
                            .font(.title2.bold())
                        Text("派蒙、快捷工具和本机信息都在这里。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(DashboardModule.allCases) { module in
                            Button {
                                store.setModule(module, hidden: !store.hiddenModules.contains(module))
                            } label: {
                                Label(
                                    module.title,
                                    systemImage: store.hiddenModules.contains(module)
                                        ? "square"
                                        : "checkmark.square.fill"
                                )
                            }
                        }
                    } label: {
                        Label("管理模块", systemImage: "slider.horizontal.3")
                    }
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.visibleModules) { module in
                        WorkspaceModuleCard(module: module, store: store) {
                            moduleBody(module)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func moduleBody(_ module: DashboardModule) -> some View {
        switch module {
        case .music:
            HStack(spacing: 12) {
                MusicArtworkView(data: music.snapshot.artworkData, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.snapshot.title.isEmpty ? "Apple Music" : music.snapshot.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(music.snapshot.artist.isEmpty ? "点击打开完整控制" : music.snapshot.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    music.send(.playPause)
                } label: {
                    Image(systemName: music.snapshot.playbackState == .playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                Button { onOpenUtility(.music) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain)
            }
        case .timer:
            VStack(alignment: .leading, spacing: 10) {
                if timer.state.phase == .idle {
                    Text("开始一段不被打扰的专注时间。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("专注 25 分钟") { timer.begin(seconds: 25 * 60) }
                            .buttonStyle(.borderedProminent)
                        Button("休息 5 分钟") { timer.begin(seconds: 5 * 60) }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Text(TimerTextFormatter.clock(seconds: timer.remainingSeconds))
                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    ProgressView(value: timer.progress)
                    Button("打开完整计时器") { onOpenUtility(.timer) }
                }
            }
        case .system:
            HStack(spacing: 18) {
                metric(
                    title: "电量",
                    value: systemStatus.snapshot.battery?.percentage.map { "\($0)%" } ?? "--",
                    symbol: "battery.75percent"
                )
                metric(
                    title: "音量",
                    value: systemStatus.snapshot.audio?.percentage.map { "\($0)%" } ?? "--",
                    symbol: systemStatus.snapshot.audio?.isMuted == true
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                Spacer()
                Button("详情") { onOpenUtility(.system) }
            }
        case .files:
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(fileShelf.items.count) 个暂存项目")
                        .font(.headline)
                    Text(fileShelf.items.first?.displayName ?? "把文件拖到刘海即可暂存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("打开") { onOpenUtility(.files) }
            }
        case .todos:
            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.pendingTodos.count) 项未完成")
                    .font(.headline)
                ForEach(store.pendingTodos.prefix(3)) { todo in
                    HStack(spacing: 7) {
                        Image(systemName: "circle")
                            .font(.caption)
                        Text(todo.title).lineLimit(1)
                        Spacer()
                    }
                    .font(.callout)
                }
                Button("管理待办") { model.selection = .todos }
            }
        case .notes:
            VStack(alignment: .leading, spacing: 8) {
                if let note = store.activeNotes.first {
                    Text(note.title).font(.headline).lineLimit(1)
                    Text(note.body.isEmpty ? "这条随笔还没有正文" : note.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text("随手记下一点什么吧。")
                        .foregroundStyle(.secondary)
                }
                Button("打开随笔记") { model.selection = .notes }
            }
        case .launcher:
            VStack(alignment: .leading, spacing: 10) {
                if let current = launcher.currentApplication {
                    Button {
                        launcher.launch(current)
                    } label: {
                        HStack {
                            Image(nsImage: current.icon)
                                .resizable()
                                .frame(width: 28, height: 28)
                            Text("返回 \(current.name)")
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 12) {
                    ForEach(launcher.commonApplications.prefix(6)) { app in
                        Button { launcher.launch(app) } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                Text(app.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 48)
                        }
                        .buttonStyle(.plain)
                        .help("打开 \(app.name)")
                    }
                }
            }
        case .agent:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    agentCenter.isListening ? "已连接本机任务提醒" : "任务提醒未连接",
                    systemImage: agentCenter.isListening ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle"
                )
                .font(.headline)
                Text(agentCenter.lastEvent.map {
                    "\($0.source.displayName)：\($0.title)"
                } ?? agentCenter.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            }
        case .recorder:
            HStack(spacing: 12) {
                Button {
                    recording.toggleRecording()
                } label: {
                    Label(
                        recording.isRecording ? "停止并保存" : "开始录音",
                        systemImage: recording.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(recording.isRecording ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.isRecording ? "正在录音……" : "\(recording.recordings.count) 条录音")
                        .font(.headline)
                    Text(recording.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("管理") { model.selection = .recordings }
            }
        case .mirror:
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("按需开启的桌面镜子")
                        .font(.headline)
                    Text("离开镜子页后立即释放摄像头。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开镜子") { model.selection = .mirror }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

private struct WorkspaceModuleCard<Content: View>: View {
    let module: DashboardModule
    @ObservedObject var store: ProductivityStore
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(module.title, systemImage: module.systemImage)
                    .font(.headline)
                Spacer()
                Menu {
                    Button("向前移动") { store.moveModule(module, offset: -1) }
                    Button("向后移动") { store.moveModule(module, offset: 1) }
                    Divider()
                    Button("隐藏模块") { store.setModule(module, hidden: true) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }
            content()
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct ProductivityTodosView: View {
    @ObservedObject var store: ProductivityStore
    @State private var title = ""
    @State private var category = "今天"
    @State private var hasDeadline = false
    @State private var deadline = Date().addingTimeInterval(3_600)
    private let categories = ["今天", "工作", "学习", "生活"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("新增待办……", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTodo)
                Picker("分类", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                Toggle("截止时间", isOn: $hasDeadline)
                    .toggleStyle(.switch)
                if hasDeadline {
                    DatePicker("", selection: $deadline, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Button("添加", action: addTodo)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)

            Divider()

            if store.todos.isEmpty {
                ContentUnavailableView(
                    "还没有待办",
                    systemImage: "checkmark.circle",
                    description: Text("新增一件今天要完成的小事吧。")
                )
            } else {
                List {
                    ForEach(store.todos) { todo in
                        HStack(spacing: 12) {
                            Button { store.toggleTodo(id: todo.id) } label: {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .strikethrough(todo.isCompleted)
                                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                                HStack(spacing: 8) {
                                    Text(todo.category)
                                    if let deadline = todo.deadline {
                                        Text(deadline.formatted(date: .abbreviated, time: .shortened))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { store.deleteTodo(id: todo.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func addTodo() {
        guard store.addTodo(
            title: title,
            category: category,
            deadline: hasDeadline ? deadline : nil
        ) != nil else { return }
        title = ""
        hasDeadline = false
    }
}

private struct ProductivityNotesView: View {
    @ObservedObject var store: ProductivityStore
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("随笔记").font(.headline)
                    Spacer()
                    Button {
                        selection = store.createNote().id
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                Divider()
                List(store.activeNotes, selection: $selection) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title).lineLimit(1)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note.id)
                }
            }
            .frame(minWidth: 210, idealWidth: 250)

            if let selection,
               let note = store.notes.first(where: { $0.id == selection }) {
                ProductivityNoteEditor(note: note, store: store)
                    .id(note.id)
            } else {
                ContentUnavailableView(
                    "选择一条随笔",
                    systemImage: "note.text",
                    description: Text("或点击左上角创建新随笔。")
                )
            }
        }
    }
}

private struct ProductivityNoteEditor: View {
    let note: ProductivityNote
    @ObservedObject var store: ProductivityStore
    @State private var title: String
    @State private var noteBody: String

    init(note: ProductivityNote, store: ProductivityStore) {
        self.note = note
        self.store = store
        _title = State(initialValue: note.title)
        _noteBody = State(initialValue: note.body)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("标题", text: $title)
                    .font(.title3.bold())
                    .textFieldStyle(.plain)
                Spacer()
                Button("智能标题") {
                    title = ProductivityNoteTitle.derive(from: noteBody)
                }
                Button("保存", action: save)
                    .buttonStyle(.borderedProminent)
                Menu {
                    Button("归档") { store.archiveNote(id: note.id) }
                    Button("删除", role: .destructive) { store.deleteNote(id: note.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
            .padding(16)
            Divider()
            TextEditor(text: $noteBody)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(14)
        }
        .onDisappear(perform: save)
    }

    private func save() {
        store.updateNote(id: note.id, title: title, body: noteBody)
    }
}

private struct ProductivityLinksView: View {
    @ObservedObject var store: ProductivityStore
    @State private var urlText = ""
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                TextField("标题（可选）", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button("收藏") {
                    if store.addLink(rawURL: urlText, title: title) != nil {
                        urlText = ""
                        title = ""
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            Divider()
            if store.links.isEmpty {
                ContentUnavailableView(
                    "还没有收藏链接",
                    systemImage: "link",
                    description: Text("只允许公开的 HTTP/HTTPS 地址。")
                )
            } else {
                List(store.links) { link in
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.title).font(.headline).lineLimit(1)
                            Text(link.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("打开") { NSWorkspace.shared.open(link.url) }
                        Button(role: .destructive) { store.deleteLink(id: link.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ProductivityClipboardView: View {
    @ObservedObject var store: ProductivityStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(
                        "记录剪贴板文字历史",
                        isOn: Binding(
                            get: { store.clipboardHistoryEnabled },
                            set: { store.setClipboardHistoryEnabled($0) }
                        )
                    )
                    .font(.headline)
                    Text("默认关闭；不会记录图片、超长文本或疑似密码和密钥的内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清空", role: .destructive, action: store.clearClipboardHistory)
                    .disabled(store.clipboardEntries.isEmpty)
            }
            .padding(18)
            Divider()
            if store.clipboardEntries.isEmpty {
                ContentUnavailableView(
                    "没有剪贴板历史",
                    systemImage: "clipboard",
                    description: Text(store.clipboardHistoryEnabled ? "复制一段普通文字后会显示在这里。" : "开启后才会记录新内容。")
                )
            } else {
                List(store.clipboardEntries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.text)
                            .lineLimit(3)
                            .textSelection(.enabled)
                        Spacer()
                        Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("复制") { store.copyToPasteboard(entry.text) }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ProductivityRecordingsView: View {
    @ObservedObject var recording: RecordingController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    recording.toggleRecording()
                } label: {
                    Label(
                        recording.isRecording ? "停止并保存" : "开始录音",
                        systemImage: recording.isRecording ? "stop.fill" : "mic.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(recording.isRecording ? .red : .accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(recording.statusText)
                        .font(.callout)
                    Text("音频和转写索引只保存在这台 Mac。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if recording.isTranscribing { ProgressView().controlSize(.small) }
            }
            .padding(18)
            Divider()

            if recording.recordings.isEmpty {
                ContentUnavailableView(
                    "还没有录音",
                    systemImage: "waveform",
                    description: Text("主动点击开始后才会请求麦克风权限。")
                )
            } else {
                List(recording.recordings) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                item.createdAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "waveform.circle.fill"
                            )
                            Spacer()
                            Text(durationText(item.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button("播放") { recording.play(item) }
                            Button("定位") { recording.reveal(item) }
                            Button("删除", role: .destructive) { recording.delete(item) }
                        }
                        if !item.transcript.isEmpty {
                            Text(item.transcript)
                                .font(.callout)
                                .textSelection(.enabled)
                        } else {
                            Text("暂无转写")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct ProductivityMirrorView: View {
    @ObservedObject var mirror: MirrorCameraController

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.88))
                if mirror.isRunning {
                    MirrorSessionView(session: mirror.session)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 44))
                        Text("镜子未开启")
                            .font(.title3.bold())
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: 720, maxHeight: 460)
            .aspectRatio(16 / 10, contentMode: .fit)

            HStack {
                Text(mirror.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if mirror.isRunning {
                    Button("关闭镜子") { mirror.stop() }
                } else {
                    Button("开启镜子") { mirror.start() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: 720)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { mirror.stop() }
    }
}

private struct ProductivityVaultView: View {
    @ObservedObject var vault: CredentialVaultController
    @ObservedObject var store: ProductivityStore
    @State private var label = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var kind = "账号"
    @State private var revealed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("macOS Keychain 本机保险箱", systemImage: "lock.shield.fill")
                        .font(.headline)
                    Spacer()
                    Text("不上传·不同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Picker("类型", selection: $kind) {
                        ForEach(["账号", "API Key", "其他"], id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 110)
                    TextField("名称", text: $label)
                        .textFieldStyle(.roundedBorder)
                    TextField("账号（可选）", text: $account)
                        .textFieldStyle(.roundedBorder)
                    SecureField("密码或 Key", text: $secret)
                        .textFieldStyle(.roundedBorder)
                    Button("加密保存", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secret.isEmpty)
                }
                Text(vault.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            Divider()

            if vault.credentials.isEmpty {
                ContentUnavailableView(
                    "保险箱是空的",
                    systemImage: "key.horizontal",
                    description: Text("密文仅保存在当前 Mac 的 Keychain 中。")
                )
            } else {
                List {
                    ForEach(vault.credentials, id: \.id) { (credential: VaultCredential) in
                        HStack(spacing: 12) {
                        Image(systemName: credential.kind == "API Key" ? "key.fill" : "person.crop.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credential.label).font(.headline)
                            Text(credential.account.isEmpty ? credential.kind : credential.account)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(revealed.contains(credential.id) ? credential.secret : String(repeating: "•", count: min(max(credential.secret.count, 6), 16)))
                            .font(.body.monospaced())
                        Button {
                            if revealed.contains(credential.id) {
                                revealed.remove(credential.id)
                            } else {
                                revealed.insert(credential.id)
                            }
                        } label: {
                            Image(systemName: revealed.contains(credential.id) ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        Button("复制") {
                            store.copyToPasteboard(credential.secret)
                        }
                        Button("删除", role: .destructive) { vault.delete(id: credential.id) }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private func add() {
        guard vault.add(label: label, account: account, secret: secret, kind: kind) else { return }
        label = ""
        account = ""
        secret = ""
    }
}
