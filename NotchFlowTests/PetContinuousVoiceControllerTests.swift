import XCTest
@testable import NotchFlow

final class PetContinuousVoiceControllerTests: XCTestCase {
    func testTranscriptNormalizationRemovesRepeatedWhitespace() {
        XCTAssertEqual(
            PetContinuousVoicePolicy.normalizedTranscript("  你好   派蒙\n"),
            "你好 派蒙"
        )
        XCTAssertNil(PetContinuousVoicePolicy.normalizedTranscript(" \n "))
    }

    func testRecentDuplicateTranscriptIsSuppressed() {
        XCTAssertFalse(
            PetContinuousVoicePolicy.shouldAccept(
                transcript: "你好派蒙",
                previousTranscript: "你好派蒙",
                secondsSincePrevious: 2
            )
        )
        XCTAssertTrue(
            PetContinuousVoicePolicy.shouldAccept(
                transcript: "你好派蒙",
                previousTranscript: "你好派蒙",
                secondsSincePrevious: 6
            )
        )
        XCTAssertTrue(
            PetContinuousVoicePolicy.shouldAccept(
                transcript: "换一个话题",
                previousTranscript: "你好派蒙",
                secondsSincePrevious: 1
            )
        )
    }

    func testConversationStopsAtEitherSafetyLimit() {
        XCTAssertFalse(
            PetContinuousVoicePolicy.shouldStop(turns: 2, elapsed: 30)
        )
        XCTAssertTrue(
            PetContinuousVoicePolicy.shouldStop(
                turns: PetContinuousVoicePolicy.maximumTurns,
                elapsed: 30
            )
        )
        XCTAssertTrue(
            PetContinuousVoicePolicy.shouldStop(
                turns: 1,
                elapsed: PetContinuousVoicePolicy.maximumDuration
            )
        )
    }

    func testVoicePhaseReportsActiveAndUserFacingState() {
        XCTAssertFalse(PetContinuousVoicePhase.idle.isActive)
        XCTAssertTrue(PetContinuousVoicePhase.listening.isActive)
        XCTAssertEqual(PetContinuousVoicePhase.speaking.displayName, "派蒙正在说话")
        XCTAssertFalse(PetContinuousVoicePhase.failed("测试").isActive)
    }
}
