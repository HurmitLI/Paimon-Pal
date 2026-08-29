import AppKit
import Combine
import SwiftUI

enum UtilitySection: String, CaseIterable, Identifiable {
    case music
    case files
    case system
    case timer

    var id: Self { self }

    var title: String {
        switch self {
        case .music: "音乐"
        case .files: "文件架"
        case .system: "系统"
        case .timer: "计时器"
        }
    }
}

@MainActor
private final class UtilityWindowModel: ObservableObject {
    @Published var selection: UtilitySection = .music
}

@MainActor
final class UtilityWindowController {
    private let window: NSWindow
    private let model = UtilityWindowModel()
    private let preferences: AppPreferences

    init(
        music: MusicController,
        fileShelf: FileShelfController,
        systemStatus: SystemStatusController,
        timer: TimerController,
        preferences: AppPreferences
    ) {
        self.preferences = preferences
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paimon Pal"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 420, height: 360)
        window.setFrameAutosaveName("NotchFlow.UtilityWindow")

        let hostingView = NSHostingView(rootView: UtilityRootView(
            model: model,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer,
            preferences: preferences
        ))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    func show(section: UtilitySection = .music) {
        model.selection = isEnabled(section) ? section : firstEnabledSection ?? section
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var firstEnabledSection: UtilitySection? {
        UtilitySection.allCases.first(where: isEnabled)
    }

    private func isEnabled(_ section: UtilitySection) -> Bool {
        switch section {
        case .music: preferences.musicEnabled
        case .files: preferences.fileShelfEnabled
        case .system: preferences.systemStatusEnabled
        case .timer: preferences.timerEnabled
        }
    }
}

private struct UtilityRootView: View {
    @ObservedObject var model: UtilityWindowModel
    @ObservedObject var music: MusicController
    @ObservedObject var fileShelf: FileShelfController
    @ObservedObject var systemStatus: SystemStatusController
    @ObservedObject var timer: TimerController
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Paimon Pal 功能窗口")
                    .font(.title2.bold())
                Text("复杂内容使用普通窗口，不固定遮挡当前应用。")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker("功能", selection: $model.selection) {
                ForEach(enabledSections) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            if enabledSections.isEmpty {
                ContentUnavailableView(
                    "所有功能均已关闭",
                    systemImage: "switch.2",
                    description: Text("可在设置的“功能”页重新开启。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    switch model.selection {
                    case .music:
                        ScrollView {
                            MusicControlView(music: music)
                                .padding(.vertical, 2)
                        }
                    case .files:
                        FileShelfView(shelf: fileShelf)
                    case .system:
                        SystemStatusView(systemStatus: systemStatus)
                    case .timer:
                        TimerView(timer: timer)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Text("第四阶段开发段 4.2：功能可独立开关。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { reconcileSelection() }
        .onChange(of: enabledSections) { _, _ in reconcileSelection() }
    }

    private var enabledSections: [UtilitySection] {
        UtilitySection.allCases.filter { section in
            switch section {
            case .music: preferences.musicEnabled
            case .files: preferences.fileShelfEnabled
            case .system: preferences.systemStatusEnabled
            case .timer: preferences.timerEnabled
            }
        }
    }

    private func reconcileSelection() {
        guard !enabledSections.contains(model.selection),
              let first = enabledSections.first
        else { return }
        model.selection = first
    }
}
