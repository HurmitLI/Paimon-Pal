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
}
