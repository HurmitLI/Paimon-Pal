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
}
