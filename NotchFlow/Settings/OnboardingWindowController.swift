import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(preferences: AppPreferences) {
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 570),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 Paimon Pal"
        window.level = .normal
        window.collectionBehavior = [.managed]
        window.isReleasedWhenClosed = false
        window.center()

        let onboardingWindow = window
        let hostingView = NSHostingView(rootView: OnboardingView(
            onLater: { [weak onboardingWindow] in
                onboardingWindow?.orderOut(nil)
            },
            onComplete: { [weak preferences, weak onboardingWindow] in
                preferences?.completeOnboarding()
                onboardingWindow?.orderOut(nil)
            }
        ))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct OnboardingView: View {
    let onLater: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 62, height: 62)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("欢迎使用 Paimon Pal")
                        .font(.largeTitle.bold())
                    Text("把 MacBook 刘海变成随手可用的状态与快捷操作入口。")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                guideRow(
                    icon: "cursorarrow.motionlines",
                    title: "从刘海开始",
                    detail: "鼠标移到刘海会显示预览；点击展开或收起；右键可打开设置和完整功能窗口。"
                )
                guideRow(
                    icon: "square.grid.2x2",
                    title: "四项功能互不依赖",
                    detail: "Apple Music、文件架、系统状态和计时器都可以在设置中单独关闭。"
                )
                guideRow(
                    icon: "lock.shield",
                    title: "权限按需申请",
                    detail: "阅读本页不会申请权限。Apple Music 和通知只会在你使用相关功能时请求。"
                )
            }

            GroupBox("本地数据与文件安全") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("不上传音乐、文件或系统状态，不含广告与行为追踪。", systemImage: "checkmark.circle.fill")
                    Label("文件架只复制你主动选择或拖入的内容，Finder 原文件不会被移动或删除。", systemImage: "checkmark.circle.fill")
                    Label("暂存副本保存在本机应用目录，默认保留 24 小时，可由你提前删除。", systemImage: "checkmark.circle.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(8)
            }

            Spacer(minLength: 0)

            HStack {
                Text("之后可在“设置 → 关于”重新查看本说明。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("稍后") { onLater() }
                Button("开始使用") { onComplete() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 640, height: 570, alignment: .topLeading)
    }

    private func guideRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.cyan)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
