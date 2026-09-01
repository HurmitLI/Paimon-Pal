import XCTest
@testable import NotchFlow

final class PetToolRouterTests: XCTestCase {
    func testParsesTimerDurations() {
        XCTAssertEqual(
            PetToolRouter.command(from: "帮我计时 5 分钟"),
            .startTimer(seconds: 300)
        )
        XCTAssertEqual(
            PetToolRouter.command(from: "倒计时30秒"),
            .startTimer(seconds: 30)
        )
        XCTAssertEqual(
            PetToolRouter.command(from: "提醒我2小时后休息"),
            .startTimer(seconds: 7_200)
        )
    }

    func testDoesNotTurnOrdinaryDurationIntoToolCall() {
        XCTAssertNil(PetToolRouter.command(from: "我刚刚学习了 5 分钟"))
        XCTAssertNil(PetToolRouter.command(from: "帮我计时零分钟"))
        XCTAssertNil(PetToolRouter.command(from: "倒计时 99999 小时"))
    }

    func testParsesTimerLifecycleCommands() {
        XCTAssertEqual(PetToolRouter.command(from: "暂停计时"), .timer(.pause))
        XCTAssertEqual(PetToolRouter.command(from: "继续倒计时"), .timer(.resume))
        XCTAssertEqual(PetToolRouter.command(from: "取消这次计时"), .timer(.cancel))
        XCTAssertEqual(PetToolRouter.command(from: "倒计时还剩多久"), .timer(.status))
    }

    func testParsesAppleMusicControlCommands() {
        XCTAssertEqual(PetToolRouter.command(from: "播放音乐"), .music(.play))
        XCTAssertEqual(PetToolRouter.command(from: "暂停音乐"), .music(.pause))
        XCTAssertEqual(PetToolRouter.command(from: "下一首"), .music(.next))
        XCTAssertEqual(PetToolRouter.command(from: "切到上一首"), .music(.previous))
        XCTAssertEqual(PetToolRouter.command(from: "现在播放的什么歌"), .music(.status))
    }

    func testDoesNotTreatOrdinaryConversationAsMediaControl() {
        XCTAssertNil(PetToolRouter.command(from: "我喜欢听音乐"))
        XCTAssertNil(PetToolRouter.command(from: "我刚才暂停了一下工作"))
        XCTAssertNil(PetToolRouter.command(from: "下一首诗写得真好"))
    }

    func testParsesExistingFeatureWindows() {
        XCTAssertEqual(PetToolRouter.command(from: "帮我打开计时器"), .open(.timer))
        XCTAssertEqual(PetToolRouter.command(from: "打开音乐窗口"), .open(.music))
        XCTAssertEqual(PetToolRouter.command(from: "让我看看文件架"), .open(.files))
        XCTAssertEqual(PetToolRouter.command(from: "查看系统状态"), .open(.system))
        XCTAssertEqual(PetToolRouter.command(from: "带我去设置"), .open(.settings))
        XCTAssertEqual(PetToolRouter.command(from: "打开工作台"), .open(.workspace))
        XCTAssertEqual(PetToolRouter.command(from: "查看待办"), .open(.todos))
        XCTAssertEqual(PetToolRouter.command(from: "打开随笔"), .open(.notes))
        XCTAssertEqual(PetToolRouter.command(from: "看看收藏链接"), .open(.links))
        XCTAssertEqual(PetToolRouter.command(from: "查看剪贴板"), .open(.clipboard))
        XCTAssertEqual(PetToolRouter.command(from: "打开录音"), .open(.recordings))
        XCTAssertEqual(PetToolRouter.command(from: "打开镜子"), .open(.mirror))
        XCTAssertEqual(PetToolRouter.command(from: "查看保险箱"), .open(.vault))
    }

    func testParsesExplicitTodoAndNoteCreationWithoutInterceptingChat() {
        XCTAssertEqual(
            PetToolRouter.command(from: "添加待办：下午三点复习"),
            .addTodo(title: "下午三点复习")
        )
        XCTAssertEqual(
            PetToolRouter.command(from: "记笔记 今天的灵感是刘海与宠物联动"),
            .addNote(body: "今天的灵感是刘海与宠物联动")
        )
        XCTAssertNil(PetToolRouter.command(from: "我的待办事项太多了"))
        XCTAssertNil(PetToolRouter.command(from: "我在记笔记"))
    }

    func testDoesNotOpenAmbiguousTargets() {
        XCTAssertNil(PetToolRouter.command(from: "帮我打开一个文件"))
        XCTAssertNil(PetToolRouter.command(from: "查看今天的状态"))
    }

    func testConversationContextUsesStructuredRequestWithoutHistory() {
        let request = PetConversationContextBuilder.request(
            history: [],
            latestUserMessage: "今天有点累"
        )

        XCTAssertEqual(request.prompt, "今天有点累")
        XCTAssertTrue(request.history.isEmpty)
        XCTAssertFalse(request.enableThinking)
    }

    func testConversationContextKeepsOnlyTheLatestEightStructuredMessages() {
        let history = (1...10).map { index in
            PetConversationMessage(
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: "消息\(index)"
            )
        }

        let request = PetConversationContextBuilder.request(
            history: history,
            latestUserMessage: "接着说"
        )

        XCTAssertEqual(request.history.count, 8)
        XCTAssertEqual(request.history.first?.content, "消息3")
        XCTAssertEqual(request.history.first?.role, .user)
        XCTAssertEqual(request.history.last?.content, "消息10")
        XCTAssertEqual(request.history.last?.role, .assistant)
        XCTAssertEqual(request.prompt, "接着说")
    }

    func testConversationContextPreservesRolesAndEnablesReasoningForFollowUp() {
        let request = PetConversationContextBuilder.request(
            history: [
                PetConversationMessage(role: .user, text: "我今天有点累"),
                PetConversationMessage(role: .assistant, text: "那就慢慢来吧。")
            ],
            latestUserMessage: "怎么个慢慢来法？"
        )

        XCTAssertEqual(request.history[0].role, .user)
        XCTAssertEqual(request.history[1].role, .assistant)
        XCTAssertEqual(request.prompt, "怎么个慢慢来法？")
        XCTAssertTrue(request.enableThinking)
    }

    func testReasoningPolicyKeepsGreetingsFastAndThinksAboutMeaning() {
        XCTAssertFalse(
            PetReasoningPolicy.shouldThink(about: "你好", hasHistory: false)
        )
        XCTAssertFalse(
            PetReasoningPolicy.shouldThink(about: "我今天有点累", hasHistory: true)
        )
        XCTAssertTrue(
            PetReasoningPolicy.shouldThink(about: "为什么会这样？", hasHistory: false)
        )
        XCTAssertTrue(
            PetReasoningPolicy.shouldThink(about: "这个具体怎么做？", hasHistory: true)
        )
    }

    func testRecallResolverUsesLatestUserMessageInsteadOfModelGuessing() {
        let reply = PetConversationRecallResolver.reply(
            history: [
                PetConversationMessage(role: .assistant, text: "我们重新聊。"),
                PetConversationMessage(role: .user, text: "我今天有点累"),
                PetConversationMessage(role: .assistant, text: "先休息一下吧。")
            ],
            latestUserMessage: "我刚才说什么了？"
        )

        XCTAssertEqual(reply, "你刚才说“我今天有点累”呀。")
    }

    func testRecallResolverRefusesToInventMemoryAfterConversationIsCleared() {
        let reply = PetConversationRecallResolver.reply(
            history: [
                PetConversationMessage(role: .assistant, text: "这一段已经清空啦。")
            ],
            latestUserMessage: "我刚才说自己怎么了？"
        )

        XCTAssertEqual(reply, "这段对话已经清空啦，我现在没有可以回看的内容。")
    }

    func testRecallResolverDoesNotInterceptOrdinaryConversation() {
        XCTAssertNil(
            PetConversationRecallResolver.reply(
                history: [],
                latestUserMessage: "我今天有点累"
            )
        )
    }

    func testBehaviorFeedbackResolverAnswersRepeatedTravelerConcernDirectly() {
        let reply = PetConversationBehaviorFeedbackResolver.reply(
            latestUserMessage: "你好像每次跟我对话都会加一个旅行者，是吧？"
        )

        XCTAssertEqual(
            reply,
            "你发现得没错，刚才语音会固定加上“旅行者”，听起来确实很重复。以后我只会在合适的时候偶尔这样称呼，不会每句话都加啦。"
        )
        XCTAssertNil(
            PetConversationBehaviorFeedbackResolver.reply(
                latestUserMessage: "旅行者今天要去哪里？"
            )
        )
    }
}

@MainActor
final class PetToolExecutorTests: XCTestCase {
    func testTimerExecutorRunsPauseResumeStatusAndCancelLifecycle() {
        let timer = TimerController(
            coordinator: ActivityCoordinator(),
            store: PetToolTimerStoreStub()
        )
        timer.begin(seconds: 120)

        let pauseReply = PetTimerToolExecutor.execute(.pause, timer: timer)
        XCTAssertEqual(timer.state.phase, .paused)
        XCTAssertTrue(pauseReply.contains("已暂停"))

        let statusReply = PetTimerToolExecutor.execute(.status, timer: timer)
        XCTAssertTrue(statusReply.contains("暂停状态"))
        XCTAssertTrue(statusReply.contains("还剩"))

        let resumeReply = PetTimerToolExecutor.execute(.resume, timer: timer)
        XCTAssertEqual(timer.state.phase, .running)
        XCTAssertTrue(resumeReply.contains("继续计时"))

        let cancelReply = PetTimerToolExecutor.execute(.cancel, timer: timer)
        XCTAssertEqual(timer.state.phase, .idle)
        XCTAssertEqual(cancelReply, "好哒，这次计时已经取消。")
        XCTAssertEqual(
            PetTimerToolExecutor.execute(.cancel, timer: timer),
            "现在没有正在运行的计时。"
        )
    }

    func testMusicExecutorDispatchesEveryExplicitCommandAndReportsStatus() {
        let statusProvider = PetToolMusicProviderStub(
            snapshot: makeMusicSnapshot(state: .playing)
        )
        let statusMusic = MusicController(
            coordinator: ActivityCoordinator(),
            provider: statusProvider
        )

        let status = PetMusicToolExecutor.execute(
            .status,
            music: statusMusic,
            isEnabled: true,
            onOpenSettings: {}
        )
        XCTAssertTrue(status.contains("《Song》"))
        XCTAssertTrue(status.contains("Artist"))

        let cases: [(PetMusicAction, MusicPlaybackState, MusicCommand)] = [
            (.play, .paused, .play),
            (.pause, .playing, .pause),
            (.next, .playing, .next),
            (.previous, .playing, .previous)
        ]
        for (action, state, command) in cases {
            let provider = PetToolMusicProviderStub(snapshot: makeMusicSnapshot(state: state))
            let music = MusicController(coordinator: ActivityCoordinator(), provider: provider)

            let reply = PetMusicToolExecutor.execute(
                action,
                music: music,
                isEnabled: true,
                onOpenSettings: {}
            )

            XCTAssertTrue(reply.contains("发送"))
            XCTAssertEqual(provider.commands, [command])
        }
    }

    func testMusicExecutorDoesNotPretendSuccessWhenUnavailableOrDenied() {
        let stoppedProvider = PetToolMusicProviderStub(snapshot: .unavailable)
        let stoppedMusic = MusicController(
            coordinator: ActivityCoordinator(),
            provider: stoppedProvider
        )
        let unavailableReply = PetMusicToolExecutor.execute(
            .next,
            music: stoppedMusic,
            isEnabled: true,
            onOpenSettings: {}
        )
        XCTAssertTrue(unavailableReply.contains("没有运行"))
        XCTAssertTrue(stoppedProvider.commands.isEmpty)

        let deniedProvider = PetToolMusicProviderStub(
            snapshot: makeMusicSnapshot(state: .playing),
            sendResult: .failure(.permissionDenied)
        )
        let deniedMusic = MusicController(
            coordinator: ActivityCoordinator(),
            provider: deniedProvider
        )
        let deniedReply = PetMusicToolExecutor.execute(
            .next,
            music: deniedMusic,
            isEnabled: true,
            onOpenSettings: {}
        )
        XCTAssertTrue(deniedReply.contains("没有执行成功"))
        XCTAssertTrue(deniedReply.contains("权限"))
    }

    func testMusicExecutorDoesNotReportStaleSongWhenRefreshFails() {
        let provider = PetToolMusicProviderStub(snapshot: makeMusicSnapshot(state: .playing))
        let music = MusicController(coordinator: ActivityCoordinator(), provider: provider)

        XCTAssertTrue(PetMusicToolExecutor.execute(
            .status,
            music: music,
            isEnabled: true,
            onOpenSettings: {}
        ).contains("《Song》"))

        provider.readResult = .failure(.permissionDenied)
        let reply = PetMusicToolExecutor.execute(
            .status,
            music: music,
            isEnabled: true,
            onOpenSettings: {}
        )

        XCTAssertTrue(reply.contains("无法读取 Apple Music"))
        XCTAssertTrue(reply.contains("权限"))
        XCTAssertFalse(reply.contains("《Song》"))
    }

    func testMusicExecutorOpensSettingsWhenFeatureIsDisabled() {
        let provider = PetToolMusicProviderStub(snapshot: makeMusicSnapshot(state: .playing))
        let music = MusicController(coordinator: ActivityCoordinator(), provider: provider)
        var didOpenSettings = false

        let reply = PetMusicToolExecutor.execute(
            .pause,
            music: music,
            isEnabled: false,
            onOpenSettings: { didOpenSettings = true }
        )

        XCTAssertTrue(didOpenSettings)
        XCTAssertTrue(reply.contains("音乐功能目前是关闭的"))
        XCTAssertTrue(provider.commands.isEmpty)
    }

    private func makeMusicSnapshot(state: MusicPlaybackState) -> MusicSnapshot {
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

private final class PetToolTimerStoreStub: TimerStateStoring {
    var state: TimerRuntimeState?

    func load() -> TimerRuntimeState? { state }
    func save(_ state: TimerRuntimeState) { self.state = state }
    func clear() { state = nil }
}

@MainActor
private final class PetToolMusicProviderStub: MusicPlaybackProviding {
    var snapshot: MusicSnapshot
    var sendResult: Result<Void, MusicServiceError>
    var readResult: Result<MusicSnapshot, MusicServiceError>?
    private(set) var commands: [MusicCommand] = []

    init(
        snapshot: MusicSnapshot,
        sendResult: Result<Void, MusicServiceError> = .success(())
    ) {
        self.snapshot = snapshot
        self.sendResult = sendResult
    }

    func readSnapshot() -> Result<MusicSnapshot, MusicServiceError> {
        readResult ?? .success(snapshot)
    }

    func send(_ command: MusicCommand) -> Result<Void, MusicServiceError> {
        commands.append(command)
        return sendResult
    }

    func seek(to position: TimeInterval) -> Result<Void, MusicServiceError> { .success(()) }
    func openSource() {}
}
