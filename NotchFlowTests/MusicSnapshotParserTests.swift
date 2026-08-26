import XCTest
@testable import NotchFlow

final class MusicSnapshotParserTests: XCTestCase {
    func testParserBuildsPlayingSnapshot() throws {
        let snapshot = try XCTUnwrap(MusicSnapshotParser.parse(
            ["playing", "Song", "Artist", "Album", "240", "60", "ABC"],
            artworkData: Data([1, 2, 3])
        ))

        XCTAssertEqual(snapshot.playbackState, .playing)
        XCTAssertEqual(snapshot.title, "Song")
        XCTAssertEqual(snapshot.artist, "Artist")
        XCTAssertEqual(snapshot.progress, 0.25, accuracy: 0.001)
        XCTAssertTrue(snapshot.canSeek)
    }

    func testParserClampsPositionToDuration() throws {
        let snapshot = try XCTUnwrap(MusicSnapshotParser.parse(
            ["paused", "Song", "Artist", "Album", "120", "999", "ABC"],
            artworkData: nil
        ))

        XCTAssertEqual(snapshot.position, 120)
        XCTAssertEqual(snapshot.progress, 1)
    }

    func testParserNormalizesMissingMetadataAndInvalidNumbers() throws {
        let snapshot = try XCTUnwrap(MusicSnapshotParser.parse(
            ["stopped", "—", "—", "—", "invalid", "-20", ""],
            artworkData: nil
        ))

        XCTAssertEqual(snapshot.playbackState, .stopped)
        XCTAssertEqual(snapshot.title, "")
        XCTAssertEqual(snapshot.duration, 0)
        XCTAssertEqual(snapshot.position, 0)
        XCTAssertFalse(snapshot.isActive)
    }

    func testParserRejectsIncompletePayload() {
        XCTAssertNil(MusicSnapshotParser.parse(["playing", "Song"], artworkData: nil))
    }
}

@MainActor
final class MusicControllerTests: XCTestCase {
    func testPollingSlowsDownWhenMusicIsNotPlaying() {
        XCTAssertEqual(MusicController.pollingInterval(for: .playing), .seconds(1))
        XCTAssertEqual(MusicController.pollingInterval(for: .paused), .seconds(2))
        XCTAssertEqual(MusicController.pollingInterval(for: .stopped), .seconds(2))
        XCTAssertEqual(MusicController.pollingInterval(for: .unavailable), .seconds(2))
    }

    func testPlayingSnapshotCreatesMusicActivity() {
        let coordinator = ActivityCoordinator()
        let provider = MusicProviderStub(result: .success(makeSnapshot(state: .playing)))
        let controller = MusicController(coordinator: coordinator, provider: provider)

        controller.refresh()

        XCTAssertEqual(controller.snapshot.title, "Song")
        XCTAssertEqual(coordinator.state.presentation, .compact)
        XCTAssertEqual(coordinator.state.activity?.id, "music.appleMusic")
    }

    func testUnavailableSnapshotRemovesExistingMusicActivity() {
        let coordinator = ActivityCoordinator()
        coordinator.upsert(IslandActivity(
            id: "music.appleMusic",
            kind: .music,
            title: "Old Song"
        ))
        let provider = MusicProviderStub(result: .success(.unavailable))
        let controller = MusicController(coordinator: coordinator, provider: provider)

        controller.refresh()

        XCTAssertEqual(coordinator.state.presentation, .silent)
    }

    func testPermissionWithdrawalRemovesActivityWithoutCrashingOtherModules() {
        let coordinator = ActivityCoordinator()
        coordinator.upsert(IslandActivity(
            id: "music.appleMusic",
            kind: .music,
            title: "Old Song"
        ))
        let provider = MusicProviderStub(result: .failure(.permissionDenied))
        let controller = MusicController(coordinator: coordinator, provider: provider)

        controller.refresh()

        XCTAssertEqual(coordinator.state.presentation, .silent)
        XCTAssertTrue(controller.message.contains("权限"))
    }

    private func makeSnapshot(state: MusicPlaybackState) -> MusicSnapshot {
        MusicSnapshot(
            installed: true,
            running: true,
            playbackState: state,
            trackID: "ABC",
            title: "Song",
            artist: "Artist",
            album: "Album",
            duration: 180,
            position: 30,
            artworkData: nil,
            canSeek: true
        )
    }
}

@MainActor
private final class MusicProviderStub: MusicPlaybackProviding {
    var result: Result<MusicSnapshot, MusicServiceError>

    init(result: Result<MusicSnapshot, MusicServiceError>) {
        self.result = result
    }

    func readSnapshot() -> Result<MusicSnapshot, MusicServiceError> { result }
    func send(_ command: MusicCommand) -> Result<Void, MusicServiceError> { .success(()) }
    func seek(to position: TimeInterval) -> Result<Void, MusicServiceError> { .success(()) }
    func openSource() {}
}
