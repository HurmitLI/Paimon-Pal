import Foundation

enum MusicPlaybackState: String, Equatable {
    case playing
    case paused
    case stopped
    case unavailable

    init(scriptValue: String) {
        switch scriptValue.lowercased() {
        case "playing": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: self = .unavailable
        }
    }
}

struct MusicSnapshot: Equatable {
    let installed: Bool
    let running: Bool
    let playbackState: MusicPlaybackState
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let position: TimeInterval
    let artworkData: Data?
    let canSeek: Bool

    static let unavailable = MusicSnapshot(
        installed: false,
        running: false,
        playbackState: .unavailable,
        trackID: "",
        title: "",
        artist: "",
        album: "",
        duration: 0,
        position: 0,
        artworkData: nil,
        canSeek: false
    )

    var isActive: Bool {
        running && playbackState != .stopped && !title.isEmpty
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

enum MusicCommand {
    case playPause
    case next
    case previous
}

enum MusicServiceError: LocalizedError, Equatable {
    case scriptUnavailable
    case permissionDenied
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            "Apple Music 控制脚本无法创建。"
        case .permissionDenied:
            "Paimon Pal 没有控制 Apple Music 的权限。请在系统设置的自动化权限中允许。"
        case .commandFailed(let message):
            message.isEmpty ? "Apple Music 操作失败。" : message
        }
    }
}

enum MusicSnapshotParser {
    static func parse(_ values: [String], artworkData: Data?) -> MusicSnapshot? {
        guard values.count >= 7 else { return nil }

        let state = MusicPlaybackState(scriptValue: values[0])
        let duration = parseNumber(values[4])
        let rawPosition = parseNumber(values[5])
        let position = min(max(rawPosition, 0), max(duration, 0))

        return MusicSnapshot(
            installed: true,
            running: true,
            playbackState: state,
            trackID: values[6],
            title: normalized(values[1]),
            artist: normalized(values[2]),
            album: normalized(values[3]),
            duration: max(duration, 0),
            position: position,
            artworkData: artworkData,
            canSeek: duration > 0
        )
    }

    private static func parseNumber(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func normalized(_ value: String) -> String {
        value == "—" ? "" : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
