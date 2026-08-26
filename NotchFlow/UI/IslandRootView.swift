import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var coordinator: ActivityCoordinator
    @ObservedObject var motion: MotionPreferences
    @ObservedObject var music: MusicController
    @ObservedObject var fileShelf: FileShelfController
    @ObservedObject var systemStatus: SystemStatusController
    @ObservedObject var timer: TimerController
    @ObservedObject var preferences: AppPreferences
    let onOpenUtilityWindow: (UtilitySection) -> Void
    let onOpenSettings: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .animation(motion.swiftUIAnimation, value: animationPresentation)
            .onTapGesture { handleIslandTap() }
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: $isDropTargeted,
                perform: { providers in
                    guard preferences.fileShelfEnabled else { return false }
                    return fileShelf.importDroppedProviders(providers)
                }
            )
            .onChange(of: isDropTargeted) { _, targeted in
                fileShelf.setDropTargeted(preferences.fileShelfEnabled && targeted)
            }
            .contextMenu {
                Button("打开设置…") { onOpenSettings() }
                Divider()
                Button("模拟紧凑活动") { simulateCompactActivity() }
                Button("模拟临时 HUD") { simulateHUD() }
                if preferences.musicEnabled {
                    Button("打开音乐窗口") { onOpenUtilityWindow(.music) }
                }
                if preferences.fileShelfEnabled {
                    Button("打开文件架") { onOpenUtilityWindow(.files) }
                }
                if preferences.systemStatusEnabled {
                    Button("打开系统状态") { onOpenUtilityWindow(.system) }
                }
                if preferences.timerEnabled {
                    Button("打开计时器") { onOpenUtilityWindow(.timer) }
                }
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
            compactActivityContent(activity, identityColor: .green)
        case .temporaryHUD(let activity):
            HStack(spacing: 0) {
                Image(systemName: activity.systemSymbol ?? icon(for: activity.kind))
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(activity.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                    if let progress = activity.progress {
                        systemProgress(progress)
                    }
                }
                .frame(width: 66, alignment: .trailing)
            }
        case .hoverPreview(let activity):
            if let activity {
                // Hover may oscillate around the physical camera cutout. Keep the
                // exact compact geometry so entering the notch never makes the
                // artwork, text, capsule radius, or window appear to twitch.
                compactActivityContent(activity, identityColor: .cyan)
            } else {
                Color.clear
            }
        case .expanded(let activity):
            if activity?.kind == .music {
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        musicButton(command: .previous, icon: "backward.fill", help: "上一首")
                        musicButton(
                            command: .playPause,
                            icon: music.snapshot.playbackState == .playing
                                ? "pause.fill"
                                : "play.fill",
                            help: music.snapshot.playbackState == .playing ? "暂停" : "播放"
                        )
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        musicButton(command: .next, icon: "forward.fill", help: "下一首")
                        Button(action: { onOpenUtilityWindow(.music) }) {
                            Image(systemName: "macwindow")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("打开完整音乐窗口")
                    }
                }
            } else if activity?.kind == .timer || activity?.kind == .ringingTimer {
                HStack(spacing: 0) {
                    Button(action: handleTimerPrimaryAction) {
                        Image(systemName: timerPrimaryIcon)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help(timerPrimaryHelp)

                    Spacer(minLength: 0)

                    HStack(spacing: 2) {
                        Text(timer.state.phase == .ringing
                             ? "结束"
                             : TimerTextFormatter.clock(seconds: timer.remainingSeconds))
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(timer.remainingSeconds <= 60 ? .orange : .white)
                            .lineLimit(1)
                        Button(action: { onOpenUtilityWindow(.timer) }) {
                            Image(systemName: "macwindow")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("打开完整计时器窗口")
                    }
                }
            } else if activity?.kind == .systemHUD || activity?.kind == .criticalSystem {
                HStack(spacing: 0) {
                    Image(systemName: activity?.systemSymbol ?? icon(for: activity?.kind ?? .systemHUD))
                        .foregroundStyle(activity?.kind == .criticalSystem ? .orange : .white)
                        .frame(width: 28, height: 28)
                    Spacer(minLength: 0)
                    Button(action: { onOpenUtilityWindow(.system) }) {
                        Image(systemName: "macwindow")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("打开系统状态窗口")
                }
            } else {
                HStack(spacing: 0) {
                    Button(action: simulateCompactActivity) {
                        Image(systemName: "play.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(action: { onOpenUtilityWindow(.files) }) {
                        Image(systemName: "macwindow")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("打开普通功能窗口")
                }
            }
        case .fileReceiving:
            HStack(spacing: 0) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28)
                Spacer(minLength: 0)
                if fileShelf.isImporting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                        .frame(width: 28)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 28)
                }
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
        case .hoverPreview: 17
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

    private func musicButton(
        command: MusicCommand,
        icon: String,
        help: String
    ) -> some View {
        Button { music.send(command) } label: {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(music.isPerformingCommand)
    }

    private var animationPresentation: IslandPresentation {
        coordinator.state.presentation == .hoverPreview
            ? .compact
            : coordinator.state.presentation
    }

    private func compactActivityContent(
        _ activity: IslandActivity,
        identityColor: Color
    ) -> some View {
        HStack {
            activityIdentity(
                for: activity,
                color: activityColor(activity, fallback: identityColor),
                size: 22
            )
            Spacer()
            Text(activity.title).font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private func activityIdentity(
        for activity: IslandActivity,
        color: Color,
        size: CGFloat
    ) -> some View {
        if activity.kind == .music, music.snapshot.artworkData != nil {
            MusicArtworkView(data: music.snapshot.artworkData, size: size)
        } else if (activity.kind == .timer || activity.kind == .ringingTimer),
                  music.snapshot.isActive,
                  music.snapshot.artworkData != nil {
            MusicArtworkView(data: music.snapshot.artworkData, size: size)
        } else {
            Image(systemName: activity.systemSymbol ?? icon(for: activity.kind))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }

    private func activityColor(_ activity: IslandActivity, fallback: Color) -> Color {
        if activity.kind == .ringingTimer ||
            (activity.kind == .timer && activity.detail == "即将结束") {
            return .orange
        }
        return fallback
    }

    private var timerPrimaryIcon: String {
        switch timer.state.phase {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .ringing: "checkmark"
        case .idle: "timer"
        }
    }

    private var timerPrimaryHelp: String {
        switch timer.state.phase {
        case .running: "暂停计时"
        case .paused: "继续计时"
        case .ringing: "确认计时结束"
        case .idle: "打开计时器"
        }
    }

    private func handleTimerPrimaryAction() {
        switch timer.state.phase {
        case .running: timer.pause()
        case .paused: timer.resume()
        case .ringing: timer.acknowledge()
        case .idle: onOpenUtilityWindow(.timer)
        }
    }

    private func systemProgress(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.24))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(width: 66, height: 3)
        .accessibilityLabel("状态进度")
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
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
