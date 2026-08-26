import AppKit
import SwiftUI

@MainActor
final class UtilityWindowController {
    private let window: NSWindow

    init() {
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchFlow"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 360, height: 280)
        window.setFrameAutosaveName("NotchFlow.UtilityWindow")

        let hostingView = NSHostingView(rootView: UtilityRootView())
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct UtilityRootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchFlow 功能窗口")
                    .font(.title2.bold())
                Text("复杂内容使用普通窗口，不固定遮挡当前应用。")
                    .foregroundStyle(.secondary)
            }

            Divider()

            featureRow(icon: "music.note", title: "音乐控制", detail: "后续阶段接入真实播放信息")
            featureRow(icon: "tray.full", title: "文件架", detail: "后续阶段实现文件暂存与 AirDrop")
            featureRow(icon: "timer", title: "计时器", detail: "后续阶段实现倒计时闭环")

            Spacer(minLength: 0)

            Text("第二阶段仅验证窗口形态、层级和打开/关闭交互。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
