import XCTest
@testable import NotchFlow

@MainActor
final class PetSpeechControllerTests: XCTestCase {
    func testTextPreparerPreservesReplyAndRemovesMarkdown() {
        XCTAssertEqual(
            PetSpeechTextPreparer.prepare(" **今天** [一起休息](https://example.com) 吧。 "),
            "今天 一起休息 吧。"
        )
        XCTAssertEqual(
            PetSpeechTextPreparer.prepare("旅行者，计时已经开始啦。"),
            "旅行者计时已经开始啦。"
        )
        XCTAssertEqual(
            PetSpeechTextPreparer.prepare("旅行者！  快来看看。"),
            "旅行者快来看看。"
        )
        XCTAssertNil(PetSpeechTextPreparer.prepare("```swift\nlet answer = 1\n```"))
    }

    func testTextPreparerLimitsLongReplies() {
        let prepared = PetSpeechTextPreparer.prepare(String(repeating: "好", count: 300))
        XCTAssertEqual(prepared?.count, PetSpeechTextPreparer.maximumCharacters)
        XCTAssertFalse(prepared?.hasPrefix("旅行者") == true)
    }

    func testRequestGateInvalidatesOlderTokens() {
        var gate = PetSpeechRequestGate()
        let first = gate.begin()
        XCTAssertTrue(gate.isCurrent(first))
        let second = gate.begin()
        XCTAssertFalse(gate.isCurrent(first))
        XCTAssertTrue(gate.isCurrent(second))
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(second))
    }

    func testTimerSpeechOnlyRunsOnLiveCountdownCompletion() {
        XCTAssertTrue(PetTimerSpeechPolicy.shouldSpeak(previous: .running, current: .ringing))
        XCTAssertFalse(PetTimerSpeechPolicy.shouldSpeak(previous: .idle, current: .ringing))
        XCTAssertFalse(PetTimerSpeechPolicy.shouldSpeak(previous: .ringing, current: .ringing))
        XCTAssertFalse(PetTimerSpeechPolicy.shouldSpeak(previous: .paused, current: .ringing))
    }

    func testStaleSpeechCleanupOnlyRemovesWaveFiles() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let wave = directory.appendingPathComponent("stale.wav")
        let uppercaseWave = directory.appendingPathComponent("stale.WAV")
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data([0, 1]).write(to: wave)
        try Data([0, 1]).write(to: uppercaseWave)
        try Data([0, 1]).write(to: unrelated)

        PetSpeechRuntimeLayout.removeStaleAudioFiles(
            in: directory,
            fileManager: fileManager
        )

        XCTAssertFalse(fileManager.fileExists(atPath: wave.path))
        XCTAssertFalse(fileManager.fileExists(atPath: uppercaseWave.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path))
    }

    func testDisabledVoiceDoesNotGenerate() {
        let generator = MockPetSpeechGenerator()
        let player = MockPetSpeechPlayer()
        let controller = PetSpeechController(
            isEnabled: { false },
            generator: generator,
            player: player
        )

        let scheduled = controller.speak(
            "你好",
            onPlaybackStarted: { XCTFail("不应播放") },
            onFinished: { XCTFail("未调度时由调用方处理完成状态") }
        )

        XCTAssertFalse(scheduled)
        XCTAssertTrue(generator.requests.isEmpty)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testSuccessfulGenerationStartsPlaybackAndCompletes() async {
        let generator = MockPetSpeechGenerator()
        let player = MockPetSpeechPlayer()
        let controller = PetSpeechController(
            isEnabled: { true },
            generator: generator,
            player: player
        )
        let started = expectation(description: "playback started")
        let finished = expectation(description: "playback finished")

        XCTAssertTrue(controller.speak(
            "今天有点累",
            onPlaybackStarted: { started.fulfill() },
            onFinished: { finished.fulfill() }
        ))
        await fulfillment(of: [started], timeout: 1)

        XCTAssertEqual(controller.phase, .playing)
        XCTAssertEqual(generator.requests.map(\.text), ["今天有点累"])
        XCTAssertEqual(player.playedURLs.count, 1)

        player.finishNaturally()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testGenerationFailureFallsBackAndFinishes() async {
        let generator = MockPetSpeechGenerator()
        generator.error = PetSpeechError.generationFailed("测试失败")
        let player = MockPetSpeechPlayer()
        let controller = PetSpeechController(
            isEnabled: { true },
            generator: generator,
            player: player
        )
        let finished = expectation(description: "fallback finished")

        XCTAssertTrue(controller.speak(
            "保留文字",
            onPlaybackStarted: { XCTFail("失败时不应播放") },
            onFinished: { finished.fulfill() }
        ))
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(player.playedURLs.isEmpty)
        XCTAssertNotNil(controller.lastError)
    }

    func testNewRequestCancelsPreviousPlaybackWithoutCompletingOldRequest() async {
        let generator = MockPetSpeechGenerator()
        let player = MockPetSpeechPlayer()
        let controller = PetSpeechController(
            isEnabled: { true },
            generator: generator,
            player: player
        )
        let firstStarted = expectation(description: "first started")
        var firstFinished = false

        XCTAssertTrue(controller.speak(
            "第一句",
            onPlaybackStarted: { firstStarted.fulfill() },
            onFinished: { firstFinished = true }
        ))
        await fulfillment(of: [firstStarted], timeout: 1)

        let secondStarted = expectation(description: "second started")
        XCTAssertTrue(controller.speak(
            "第二句",
            onPlaybackStarted: { secondStarted.fulfill() },
            onFinished: {}
        ))
        await fulfillment(of: [secondStarted], timeout: 1)

        XCTAssertFalse(firstFinished)
        XCTAssertEqual(player.stopCount, 2)
        XCTAssertEqual(generator.requests.map(\.text), ["第一句", "第二句"])
    }
}

@MainActor
private final class MockPetSpeechGenerator: PetSpeechGenerating {
    struct Request {
        let text: String
        let token: UUID
    }

    var requests: [Request] = []
    var error: Error?

    func generate(text: String, token: UUID) async throws -> URL {
        requests.append(Request(text: text, token: token))
        if let error { throw error }
        return URL(fileURLWithPath: "/tmp/\(token.uuidString).wav")
    }
}

@MainActor
private final class MockPetSpeechPlayer: PetSpeechAudioPlaying {
    var onPlaybackEnded: (() -> Void)?
    var playedURLs: [URL] = []
    var stopCount = 0

    func play(url: URL) throws {
        playedURLs.append(url)
    }

    func stop() {
        stopCount += 1
    }

    func finishNaturally() {
        onPlaybackEnded?()
    }
}
