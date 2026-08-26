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

    init(
        music: MusicController,
        fileShelf: FileShelfController,
        systemStatus: SystemStatusController,
        timer: TimerController
    ) {
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchFlow"
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
            timer: timer
        ))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    func show(section: UtilitySection = .music) {
        model.selection = section
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct UtilityRootView: View {
    @ObservedObject var model: UtilityWindowModel
    @ObservedObject var music: MusicController
    @ObservedObject var fileShelf: FileShelfController
    @ObservedObject var systemStatus: SystemStatusController
    @ObservedObject var timer: TimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchFlow 功能窗口")
                    .font(.title2.bold())
                Text("复杂内容使用普通窗口，不固定遮挡当前应用。")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker("功能", selection: $model.selection) {
                ForEach(UtilitySection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

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

            Text("第三阶段开发段 3.4：单计时器闭环。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
