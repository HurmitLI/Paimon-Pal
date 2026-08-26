import AppKit
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var coordinator: ActivityCoordinator
    @ObservedObject var motion: MotionPreferences
    let onOpenUtilityWindow: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(motion.swiftUIAnimation, value: coordinator.state)
            .onTapGesture { handleIslandTap() }
            .dropDestination(for: URL.self, action: { _, _ in
                coordinator.endFileReceiving()
                return false
            }, isTargeted: { targeted in
                isDropTargeted = targeted
                if targeted { coordinator.beginFileReceiving() }
                else { coordinator.endFileReceiving() }
            })
            .contextMenu {
                Button("模拟紧凑活动") { simulateCompactActivity() }
                Button("模拟临时 HUD") { simulateHUD() }
                Button("打开普通功能窗口") { onOpenUtilityWindow() }
                Divider()
                Button("清除模拟活动") { coordinator.clearAllActivities() }
                Button("退出 NotchFlow") { NSApp.terminate(nil) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .silent:
            Color.clear
        case .compact(let activity):
            HStack {
                Image(systemName: icon(for: activity.kind))
                    .foregroundStyle(.green)
                Spacer()
                Text(activity.title).font(.caption.weight(.semibold))
            }
        case .temporaryHUD(let activity):
            HStack(spacing: 0) {
                Image(systemName: icon(for: activity.kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                Spacer(minLength: 0)
                Text(activity.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 66, alignment: .trailing)
            }
        case .hoverPreview(let activity):
            HStack(spacing: 0) {
                Image(systemName: activity.map { icon(for: $0.kind) } ?? "circle.hexagongrid.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 32)
                Spacer(minLength: 0)
                if let activity {
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 58, alignment: .trailing)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 32)
                }
            }
        case .expanded(let activity):
            HStack(spacing: 0) {
                Button {
                    simulateCompactActivity()
                } label: {
                    Image(systemName: activity.map { icon(for: $0.kind) } ?? "play.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: onOpenUtilityWindow) {
                    Image(systemName: "macwindow")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("打开普通功能窗口")
            }
        case .fileReceiving:
            HStack(spacing: 0) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28)
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .frame(width: 28)
            }
        }
    }

    private var contentPadding: CGFloat {
        switch coordinator.state.presentation {
        case .silent: 0
        case .compact: 4
        case .temporaryHUD, .fileReceiving: 4
        case .hoverPreview: 4
        case .expanded: 4
        }
    }

    private var cornerRadius: CGFloat {
        switch coordinator.state.presentation {
        case .silent, .compact: 17
        case .temporaryHUD, .fileReceiving: 18
        case .hoverPreview: 18
        case .expanded: 18
        }
    }

    private func icon(for kind: IslandActivityKind) -> String {
        switch kind {
        case .fileDrop: "doc.fill"
        case .criticalSystem: "exclamationmark.triangle.fill"
        case .userInteraction: "hand.tap.fill"
        case .ringingTimer: "timer.circle.fill"
        case .timer: "timer"
        case .music: "music.note"
        case .systemHUD: "speaker.wave.2.fill"
        }
    }

    private func simulateCompactActivity() {
        coordinator.upsert(IslandActivity(
            id: "demo.music",
            kind: .music,
            title: "模拟活动",
            detail: "用于验证 S1 容器"
        ))
    }

    private func simulateHUD() {
        coordinator.showTemporaryHUD(IslandActivity(
            id: "demo.hud",
            kind: .systemHUD,
            title: "音量 50%",
            detail: "3 秒后恢复此前状态"
        ), duration: .seconds(3))
    }

    private func handleIslandTap() {
        switch coordinator.state.presentation {
        case .silent, .compact, .temporaryHUD, .hoverPreview:
            coordinator.showExpanded()
        case .expanded, .fileReceiving:
            break
        }
    }

}
