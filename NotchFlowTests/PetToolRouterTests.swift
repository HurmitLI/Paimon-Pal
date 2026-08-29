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

    func testParsesExistingFeatureWindows() {
        XCTAssertEqual(PetToolRouter.command(from: "帮我打开计时器"), .open(.timer))
        XCTAssertEqual(PetToolRouter.command(from: "打开音乐窗口"), .open(.music))
        XCTAssertEqual(PetToolRouter.command(from: "让我看看文件架"), .open(.files))
        XCTAssertEqual(PetToolRouter.command(from: "查看系统状态"), .open(.system))
        XCTAssertEqual(PetToolRouter.command(from: "带我去设置"), .open(.settings))
    }

    func testDoesNotOpenAmbiguousTargets() {
        XCTAssertNil(PetToolRouter.command(from: "我喜欢听音乐"))
        XCTAssertNil(PetToolRouter.command(from: "帮我打开一个文件"))
        XCTAssertNil(PetToolRouter.command(from: "查看今天的状态"))
    }

    func testConversationContextUsesDirectPromptWithoutHistory() {
        XCTAssertEqual(
            PetConversationContextBuilder.prompt(
                history: [],
                latestUserMessage: "今天有点累"
            ),
            "今天有点累"
        )
    }

    func testConversationContextKeepsOnlyTheLatestSixMessages() {
        let history = (1...8).map { index in
            PetConversationMessage(
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: "消息\(index)"
            )
        }

        let prompt = PetConversationContextBuilder.prompt(
            history: history,
            latestUserMessage: "接着说"
        )

        XCTAssertFalse(prompt.contains("消息1"))
        XCTAssertFalse(prompt.contains("消息2"))
        XCTAssertTrue(prompt.contains("用户：消息3"))
        XCTAssertTrue(prompt.contains("派蒙：消息8"))
        XCTAssertTrue(prompt.contains("【用户最新一句】\n接着说"))
        XCTAssertTrue(prompt.contains("必须从记录中找到对应内容并直接准确回答"))
    }

    func testConversationContextAllowsExactRecallWhenUserAsksAboutHistory() {
        let prompt = PetConversationContextBuilder.prompt(
            history: [
                PetConversationMessage(role: .user, text: "我今天有点累"),
                PetConversationMessage(role: .assistant, text: "那就先休息一下吧。")
            ],
            latestUserMessage: "我刚才说什么了？"
        )

        XCTAssertTrue(prompt.contains("用户：我今天有点累"))
        XCTAssertTrue(prompt.contains("用户明确询问前文时，可以准确复述相关内容"))
        XCTAssertTrue(prompt.hasSuffix("我刚才说什么了？"))
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
