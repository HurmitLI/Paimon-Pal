import AppKit
import Combine
import Foundation
import SwiftUI

enum MediaPlayerKind: String, CaseIterable, Identifiable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"

    var id: String { rawValue }

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var scriptApplicationName: String { rawValue }
}

struct MediaPlayerSnapshot: Equatable {
    let player: MediaPlayerKind
    let installed: Bool
    let running: Bool
    let playbackState: String
    let trackName: String
    let artistName: String
    let detail: String
}

enum MediaCommand {
    case playPause
    case next
    case previous
}

@MainActor
final class MediaControlLabModel: ObservableObject {
    @Published var selectedPlayer: MediaPlayerKind = .appleMusic
    @Published private(set) var snapshot: MediaPlayerSnapshot?
    @Published private(set) var lastMessage = "尚未测试"

    func refresh() {
        let player = selectedPlayer
        let installed = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: player.bundleIdentifier
        ) != nil
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == player.bundleIdentifier
        }

        guard installed else {
            snapshot = MediaPlayerSnapshot(
                player: player,
                installed: false,
                running: false,
                playbackState: "不可用",
                trackName: "—",
                artistName: "—",
                detail: "本机未安装 \(player.rawValue)，当前环境只能记录为不可测。"
            )
            lastMessage = "未安装 \(player.rawValue)"
            return
        }

        guard running else {
            snapshot = MediaPlayerSnapshot(
                player: player,
                installed: true,
                running: false,
                playbackState: "未运行",
                trackName: "—",
                artistName: "—",
                detail: "请先打开并播放一首歌曲，再点击读取。"
            )
            lastMessage = "\(player.rawValue) 已安装但未运行"
            return
        }

        switch execute(script: metadataScript(for: player)) {
        case .success(let output):
            let parts = output.components(separatedBy: "\n")
            snapshot = MediaPlayerSnapshot(
                player: player,
                installed: true,
                running: true,
                playbackState: value(at: 0, in: parts),
                trackName: value(at: 1, in: parts),
                artistName: value(at: 2, in: parts),
                detail: "已通过 Apple Events 读取播放状态与曲目信息。"
            )
            lastMessage = "读取成功"
        case .failure(let error):
            snapshot = MediaPlayerSnapshot(
                player: player,
                installed: true,
                running: true,
                playbackState: "读取失败",
                trackName: "—",
                artistName: "—",
                detail: error.localizedDescription
            )
            lastMessage = "读取失败：\(error.localizedDescription)"
        }
    }

    func send(_ command: MediaCommand) {
        let player = selectedPlayer
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == player.bundleIdentifier
        }) else {
            lastMessage = "请先运行 \(player.rawValue)"
            return
        }

        let action: String
        switch command {
        case .playPause: action = "playpause"
        case .next: action = "next track"
        case .previous: action = "previous track"
        }

        let source = "tell application \"\(player.scriptApplicationName)\" to \(action)"
        switch execute(script: source) {
        case .success:
            lastMessage = "指令已发送，正在等待播放器更新…"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.refresh()
            }
        case .failure(let error):
            lastMessage = "控制失败：\(error.localizedDescription)"
        }
    }

    private func metadataScript(for player: MediaPlayerKind) -> String {
        """
        tell application "\(player.scriptApplicationName)"
            set stateText to (player state as text)
            try
                set trackText to name of current track
            on error
                set trackText to "—"
            end try
            try
                set artistText to artist of current track
            on error
                set artistText to "—"
            end try
            return stateText & linefeed & trackText & linefeed & artistText
        end tell
        """
    }

    private func execute(script source: String) -> Result<String, NSError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(NSError(
                domain: "NotchFlow.MediaLab",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法创建 AppleScript"]
            ))
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(NSError(
                domain: "NotchFlow.MediaLab",
                code: errorInfo[NSAppleScript.errorNumber] as? Int ?? 2,
                userInfo: [NSLocalizedDescriptionKey:
                    errorInfo[NSAppleScript.errorMessage] as? String ?? "Apple Events 调用失败"]
            ))
        }
        return .success(result.stringValue ?? "")
    }

    private func value(at index: Int, in values: [String]) -> String {
        guard values.indices.contains(index), !values[index].isEmpty else { return "—" }
        return values[index]
    }
}

struct MediaControlLabView: View {
    @StateObject private var model = MediaControlLabModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("播放器", selection: $model.selectedPlayer) {
                ForEach(MediaPlayerKind.allCases) { player in
                    Text(player.rawValue).tag(player)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.selectedPlayer) { _, _ in model.refresh() }

            HStack {
                Button("读取播放状态") { model.refresh() }
                    .buttonStyle(.borderedProminent)
                Button("上一首") { model.send(.previous) }
                Button("播放/暂停") { model.send(.playPause) }
                Button("下一首") { model.send(.next) }
            }

            if let snapshot = model.snapshot {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("安装"); Text(snapshot.installed ? "是" : "否") }
                    GridRow { Text("运行"); Text(snapshot.running ? "是" : "否") }
                    GridRow { Text("状态"); Text(snapshot.playbackState) }
                    GridRow { Text("曲目"); Text(snapshot.trackName) }
                    GridRow { Text("艺人"); Text(snapshot.artistName) }
                }
                .font(.system(.body, design: .monospaced))
                Text(snapshot.detail).foregroundStyle(.secondary)
            }
            Text("实验结果：\(model.lastMessage)")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}
