import AppKit
import Foundation

@MainActor
protocol MusicPlaybackProviding: AnyObject {
    func readSnapshot() -> Result<MusicSnapshot, MusicServiceError>
    func send(_ command: MusicCommand) -> Result<Void, MusicServiceError>
    func seek(to position: TimeInterval) -> Result<Void, MusicServiceError>
    func openSource()
}

@MainActor
final class AppleMusicAdapter: MusicPlaybackProviding {
    private let bundleIdentifier = "com.apple.Music"
    private var cachedTrackID = ""
    private var cachedArtworkData: Data?

    func readSnapshot() -> Result<MusicSnapshot, MusicServiceError> {
        let installed = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) != nil
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }

        guard installed, running else {
            return .success(MusicSnapshot(
                installed: installed,
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
            ))
        }

        switch execute(script: metadataScript) {
        case .failure(let error):
            return .failure(error)
        case .success(let descriptor):
            let values = descriptorValues(descriptor)
            guard values.count >= 7 else {
                return .failure(.commandFailed("无法解析 Apple Music 返回的播放信息。"))
            }

            let trackID = values[6]
            if trackID != cachedTrackID {
                cachedTrackID = trackID
                cachedArtworkData = readArtworkData()
            }
            guard let snapshot = MusicSnapshotParser.parse(values, artworkData: cachedArtworkData) else {
                return .failure(.commandFailed("无法生成 Apple Music 播放快照。"))
            }
            return .success(snapshot)
        }
    }

    func send(_ command: MusicCommand) -> Result<Void, MusicServiceError> {
        let action: String
        switch command {
        case .playPause: action = "playpause"
        case .next: action = "next track"
        case .previous: action = "previous track"
        }
        return executeVoid(script: "tell application \"Music\" to \(action)")
    }

    func seek(to position: TimeInterval) -> Result<Void, MusicServiceError> {
        guard position.isFinite else {
            return .failure(.commandFailed("无效的播放进度。"))
        }
        let safePosition = max(position, 0)
        return executeVoid(
            script: "tell application \"Music\" to set player position to \(safePosition)"
        )
    }

    func openSource() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private var metadataScript: String {
        """
        tell application "Music"
            set stateText to (player state as text)
            if stateText is "stopped" then
                return {stateText, "—", "—", "—", "0", "0", ""}
            end if
            try
                set currentItem to current track
                set titleText to name of currentItem
                set artistText to artist of currentItem
                set albumText to album of currentItem
                set durationText to (duration of currentItem) as text
                set positionText to (player position) as text
                set idText to persistent ID of currentItem
                return {stateText, titleText, artistText, albumText, durationText, positionText, idText}
            on error
                return {stateText, "—", "—", "—", "0", "0", ""}
            end try
        end tell
        """
    }

    private func readArtworkData() -> Data? {
        let scripts = [
            "tell application \"Music\" to return raw data of artwork 1 of current track",
            "tell application \"Music\" to return data of artwork 1 of current track"
        ]
        for source in scripts {
            if case .success(let descriptor) = execute(script: source) {
                let data = descriptor.data
                if !data.isEmpty,
                   NSImage(data: data) != nil {
                    return data
                }
            }
        }
        return nil
    }

    private func descriptorValues(_ descriptor: NSAppleEventDescriptor) -> [String] {
        guard descriptor.numberOfItems > 0 else {
            return descriptor.stringValue.map { [$0] } ?? []
        }
        return (1...descriptor.numberOfItems).map {
            descriptor.atIndex($0)?.stringValue ?? ""
        }
    }

    private func executeVoid(script source: String) -> Result<Void, MusicServiceError> {
        switch execute(script: source) {
        case .success: .success(())
        case .failure(let error): .failure(error)
        }
    }

    private func execute(
        script source: String
    ) -> Result<NSAppleEventDescriptor, MusicServiceError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptUnavailable)
        }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {
                return .failure(.permissionDenied)
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
            return .failure(.commandFailed(message))
        }
        return .success(descriptor)
    }
}
