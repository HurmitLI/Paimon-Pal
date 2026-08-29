import SwiftUI
import UniformTypeIdentifiers

struct PetAnimationLabView: View {
    @StateObject private var model = PetAnimationPlayerModel()
    @State private var useDarkBackground = false

    var body: some View {
        HStack(spacing: 0) {
            actionSidebar
            Divider()
            playerContent
        }
        .frame(minWidth: 920, minHeight: 680)
    }

    private var actionSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("宠物动作")
                .font(.title2.bold())

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.animations) { animation in
                        Button {
                            model.selectAnimation(animation)
                        } label: {
                            HStack {
                                Text(animation.displayName)
                                Spacer()
                                if model.selectedAnimation?.id == animation.id {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                model.selectedAnimation?.id == animation.id
                                    ? Color.accentColor.opacity(0.14)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Button("重新选择素材清单…") {
                chooseManifest()
            }
            .buttonStyle(.bordered)

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(model.frames.isEmpty ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 220)
    }

    private var playerContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NotchFlow 宠物动画播放器")
                        .font(.largeTitle.bold())
                    Text("独立实验工具 · 不修改正式 NotchFlow")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("深色背景", isOn: $useDarkBackground)
                    .toggleStyle(.switch)
            }

            preview

            HStack(spacing: 10) {
                Button {
                    model.showPreviousFrame()
                } label: {
                    Label("上一帧", systemImage: "backward.frame.fill")
                }

                Button {
                    model.togglePlayback()
                } label: {
                    Label(
                        model.isPlaying ? "暂停" : "播放",
                        systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.showNextFrame()
                } label: {
                    Label("下一帧", systemImage: "forward.frame.fill")
                }

                Button {
                    model.restart()
                } label: {
                    Label("从头播放", systemImage: "arrow.counterclockwise")
                }
            }
            .buttonStyle(.bordered)

            animationDetails
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(useDarkBackground ? Color.black : Color.white)
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.quaternary, lineWidth: 1)

            if let image = model.currentImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(18)
            } else {
                ContentUnavailableView(
                    "未读取到动画",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(model.statusMessage)
                )
            }

            VStack {
                Spacer()
                HStack {
                    Text("帧 \(model.currentFrame + 1) / \(max(model.frames.count, 1))")
                    Spacer()
                    if let animation = model.selectedAnimation {
                        Text("\(animation.fps) fps · \(animation.playbackDescription)")
                    }
                }
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(useDarkBackground ? .white : .black)
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 430, maxHeight: 500)
    }

    private var animationDetails: some View {
        GroupBox("当前动作信息") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                detailRow("动作", model.selectedAnimation?.displayName ?? "—")
                detailRow("源文件", model.selectedAnimation?.source ?? "—")
                detailRow(
                    "源尺寸",
                    model.selectedAnimation.map { "\($0.sourceWidth)×\($0.sourceHeight)" } ?? "—"
                )
                detailRow("切帧结果", model.frames.isEmpty ? "未完成" : "\(model.frames.count) 帧")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func chooseManifest() {
        let panel = NSOpenPanel()
        panel.title = "选择宠物动画清单"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.loadManifest(from: url)
        }
    }
}
