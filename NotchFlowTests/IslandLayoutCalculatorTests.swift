import CoreGraphics
import XCTest
@testable import NotchFlow

final class IslandLayoutCalculatorTests: XCTestCase {
    private let notchedScreen = IslandScreenGeometry(
        screenID: "1",
        screenName: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 665, y: 950, width: 185, height: 32),
        mode: .physicalNotch
    )

    @MainActor
    func testBundledPetAssetsProvideInitialSleepingFrame() {
        let pet = NotchPetController()

        XCTAssertTrue(pet.hasRenderableFrame, pet.lastError ?? "宠物首帧未加载")
        XCTAssertEqual(pet.stage, .sleeping)
    }

    func testIdleSpriteSheetProvidesSixteenFrames() throws {
        let frames = try NotchPetAssetLoader().frames(for: .idle)

        XCTAssertEqual(frames.count, 16)
        XCTAssertTrue(frames.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
    }

    func testSpriteGridKeepsLegacyEightFrameMotions() {
        XCTAssertEqual(
            NotchPetFrameSlicer.cropRects(imageWidth: 1_536, imageHeight: 1_024).count,
            8
        )
        XCTAssertEqual(
            NotchPetFrameSlicer.cropRects(
                imageWidth: 1_254,
                imageHeight: 1_254,
                rows: 4
            ).count,
            16
        )
    }

    @MainActor
    func testPetCanEnterAndExitListeningState() async {
        let pet = NotchPetController()

        pet.startListening()
        await Task.yield()
        XCTAssertEqual(pet.stage, .listening)
        XCTAssertTrue(pet.keepsVisibleWithoutPointer)
        XCTAssertTrue(pet.acceptsConversationClick)
        XCTAssertFalse(pet.acceptsDesktopDrag)

        pet.stopListening()
        await Task.yield()
        XCTAssertEqual(pet.stage, .idle)
        XCTAssertFalse(pet.keepsVisibleWithoutPointer)
        XCTAssertTrue(pet.acceptsConversationClick)
        XCTAssertTrue(pet.acceptsDesktopDrag)
    }

    @MainActor
    func testPetCanEnterAndExitSpeakingState() async {
        let pet = NotchPetController()

        pet.startSpeaking()
        await Task.yield()
        XCTAssertEqual(pet.stage, .speaking)
        XCTAssertTrue(pet.keepsVisibleWithoutPointer)
        XCTAssertFalse(pet.acceptsConversationClick)

        pet.stopSpeaking()
        await Task.yield()
        XCTAssertEqual(pet.stage, .idle)
        XCTAssertFalse(pet.keepsVisibleWithoutPointer)
    }

    @MainActor
    func testPetSuccessCelebrationReturnsToIdle() async {
        let pet = NotchPetController()

        pet.celebrateSuccess()
        await Task.yield()
        XCTAssertEqual(pet.stage, .celebrating)
        XCTAssertTrue(pet.keepsVisibleWithoutPointer)

        try? await Task.sleep(for: .milliseconds(1_250))
        XCTAssertEqual(pet.stage, .idle)
        XCTAssertFalse(pet.keepsVisibleWithoutPointer)
    }

    @MainActor
    func testPetConversationSequenceAndSuccessPriority() async {
        let pet = NotchPetController()

        pet.startListening()
        await Task.yield()
        XCTAssertEqual(pet.stage, .listening)
        pet.returnToSleep()
        XCTAssertEqual(pet.stage, .listening)

        pet.startSpeaking()
        await Task.yield()
        XCTAssertEqual(pet.stage, .speaking)

        pet.celebrateSuccess()
        await Task.yield()
        XCTAssertEqual(pet.stage, .celebrating)

        pet.startListening()
        pet.startSpeaking()
        pet.returnToSleep()
        XCTAssertEqual(pet.stage, .celebrating)

        try? await Task.sleep(for: .milliseconds(1_250))
        XCTAssertEqual(pet.stage, .idle)
    }

    func testExpandedPhysicalIslandStaysInsideCompactTopBand() {
        let metrics = IslandLayoutCalculator.metrics(for: .expanded, geometry: notchedScreen)
        XCTAssertEqual(metrics.size.width, notchedScreen.notchRect!.width + 152)
        XCTAssertEqual(metrics.size.height, notchedScreen.notchRect!.height + 7)
        XCTAssertEqual(metrics.topOffset, 0)
    }

    @MainActor
    func testCurrentMacResolvesAtLeastOneLiveDisplay() {
        let service = ScreenGeometryService()

        XCTAssertFalse(service.availableDisplays.isEmpty)
        XCTAssertNotNil(service.current(mode: .builtIn))
        XCTAssertNotNil(service.current(mode: .primary))
    }

    func testEveryStateKeepsThePhysicalTopAnchor() {
        for presentation in IslandPresentation.allCases {
            let metrics = IslandLayoutCalculator.metrics(for: presentation, geometry: notchedScreen)
            let frame = IslandLayoutCalculator.frame(for: metrics, on: notchedScreen)
            XCTAssertEqual(frame.maxY, notchedScreen.frame.maxY)
        }
    }

    func testPetCanWakeWhileTimerOrMusicUsesCompactIsland() {
        let timer = IslandActivity(
            id: "timer",
            kind: .timer,
            title: "01:00"
        )
        let music = IslandActivity(
            id: "music",
            kind: .music,
            title: "正在播放"
        )

        XCTAssertTrue(
            NotchPetActivityVisibilityPolicy.allows(
                state: .compact(timer),
                petKeepsVisible: false
            )
        )
        XCTAssertTrue(
            NotchPetActivityVisibilityPolicy.allows(
                state: .hoverPreview(music),
                petKeepsVisible: false
            )
        )
    }

    func testPetYieldsToCriticalAndInteractiveIslandStates() {
        let ringingTimer = IslandActivity(
            id: "ringing",
            kind: .ringingTimer,
            title: "时间到"
        )
        let volumeHUD = IslandActivity(
            id: "volume",
            kind: .systemHUD,
            title: "50%"
        )

        XCTAssertFalse(
            NotchPetActivityVisibilityPolicy.allows(
                state: .compact(ringingTimer),
                petKeepsVisible: false
            )
        )
        XCTAssertFalse(
            NotchPetActivityVisibilityPolicy.allows(
                state: .temporaryHUD(volumeHUD),
                petKeepsVisible: false
            )
        )
        XCTAssertFalse(
            NotchPetActivityVisibilityPolicy.allows(
                state: .expanded(nil),
                petKeepsVisible: false
            )
        )
        XCTAssertTrue(
            NotchPetActivityVisibilityPolicy.allows(
                state: .expanded(nil),
                petKeepsVisible: true
            )
        )
    }

    func testNoNotchUsesSixPointFloatingOffset() {
        let external = IslandScreenGeometry(
            screenID: "3",
            screenName: "External",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            notchRect: nil,
            mode: .floatingCapsule
        )
        let metrics = IslandLayoutCalculator.metrics(for: .silent, geometry: external)
        let frame = IslandLayoutCalculator.frame(for: metrics, on: external)
        XCTAssertEqual(metrics.size, CGSize(width: 230, height: 37))
        XCTAssertEqual(external.frame.maxY - frame.maxY, 6)
    }

    func testNoNotchAppliesUserSpacingAndWidthAdjustment() {
        let external = IslandScreenGeometry(
            screenID: "3",
            screenName: "External",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            notchRect: nil,
            mode: .floatingCapsule
        )

        let metrics = IslandLayoutCalculator.metrics(
            for: .silent,
            geometry: external,
            externalTopOffset: 18,
            floatingWidthAdjustment: 24
        )
        let frame = IslandLayoutCalculator.frame(for: metrics, on: external)

        XCTAssertEqual(metrics.size.width, 254)
        XCTAssertEqual(external.frame.maxY - frame.maxY, 18)
    }

    func testPhysicalHoverKeepsCompactActivityOutlineStable() {
        let compact = IslandLayoutCalculator.metrics(for: .compact, geometry: notchedScreen)
        let hover = IslandLayoutCalculator.metrics(for: .hoverPreview, geometry: notchedScreen)

        XCTAssertEqual(hover.size, compact.size)
        XCTAssertEqual(hover.cornerRadius, compact.cornerRadius)
        XCTAssertEqual(hover.size.height, notchedScreen.notchRect!.height + 7)
    }

    func testEveryPhysicalIslandStateUsesTheSameNonBlockingHeight() {
        for presentation in IslandPresentation.allCases {
            let metrics = IslandLayoutCalculator.metrics(for: presentation, geometry: notchedScreen)
            XCTAssertEqual(
                metrics.size.height,
                notchedScreen.notchRect!.height + 7,
                "\(presentation.displayName) 不应向下覆盖应用内容"
            )
        }
    }

    func testDisplayTargetResolverUsesRequestedScreenAndFallsBackToPrimary() {
        let primary = DisplayDescriptor(
            id: "external", name: "External", isBuiltIn: false,
            hasNotch: false, isPrimary: true
        )
        let builtIn = DisplayDescriptor(
            id: "built-in", name: "MacBook", isBuiltIn: true,
            hasNotch: true, isPrimary: false
        )
        let displays = [primary, builtIn]

        XCTAssertEqual(
            DisplayTargetResolver.resolve(from: displays, mode: .builtIn, specificDisplayID: nil),
            builtIn
        )
        XCTAssertEqual(
            DisplayTargetResolver.resolve(from: displays, mode: .primary, specificDisplayID: nil),
            primary
        )
        XCTAssertEqual(
            DisplayTargetResolver.resolve(from: displays, mode: .specific, specificDisplayID: "built-in"),
            builtIn
        )
        XCTAssertEqual(
            DisplayTargetResolver.resolve(from: displays, mode: .specific, specificDisplayID: "missing"),
            primary
        )
    }

    func testBuiltInTargetFallsBackToPrimaryWhenLaptopDisplayIsUnavailable() {
        let primary = DisplayDescriptor(
            id: "external", name: "External", isBuiltIn: false,
            hasNotch: false, isPrimary: true
        )

        XCTAssertEqual(
            DisplayTargetResolver.resolve(from: [primary], mode: .builtIn, specificDisplayID: nil),
            primary
        )
    }

    func testFullscreenFrameMatchingUsesSmallTolerance() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

        XCTAssertTrue(FullScreenFrameMatcher.matches(
            windowBounds: CGRect(x: 1, y: 1, width: 1511, height: 981),
            displayBounds: display
        ))
        XCTAssertFalse(FullScreenFrameMatcher.matches(
            windowBounds: CGRect(x: 0, y: 24, width: 1512, height: 958),
            displayBounds: display
        ))
        XCTAssertTrue(FullScreenFrameMatcher.matches(
            windowBounds: CGRect(x: 0, y: 33, width: 1512, height: 949),
            displayBounds: display,
            allowedTopInset: 33
        ))
        XCTAssertFalse(FullScreenFrameMatcher.matches(
            windowBounds: CGRect(x: 0, y: 33, width: 1512, height: 874),
            displayBounds: display,
            allowedTopInset: 33
        ))
    }

    func testFullscreenVisibilityPolicy() {
        let normal = IslandState.compact(IslandActivity(
            id: "music", kind: .music, title: "Playing"
        ))
        let important = IslandState.temporaryHUD(IslandActivity(
            id: "battery", kind: .criticalSystem, title: "Low Battery"
        ))

        XCTAssertFalse(PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: true,
            behavior: .hidden,
            state: important
        ))
        XCTAssertFalse(PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: true,
            behavior: .importantOnly,
            state: normal
        ))
        XCTAssertTrue(PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: true,
            behavior: .importantOnly,
            state: important
        ))
        XCTAssertTrue(PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: true,
            behavior: .alwaysShow,
            state: normal
        ))
        XCTAssertFalse(PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: false,
            isTargetScreenFullscreen: false,
            behavior: .alwaysShow,
            state: normal
        ))
    }

    func testPetDesktopPlacementRoundTripsAcrossVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 60, width: 1_200, height: 800)
        let panelSize = CGSize(width: 180, height: 188)
        let original = CGRect(x: 330, y: 310, width: panelSize.width, height: panelSize.height)

        let placement = PetDesktopPlacementCalculator.placement(
            for: original,
            screenID: "display-1",
            visibleFrame: visibleFrame
        )
        let restored = PetDesktopPlacementCalculator.frame(
            for: placement,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(placement.screenID, "display-1")
        XCTAssertEqual(restored.minX, original.minX, accuracy: 0.001)
        XCTAssertEqual(restored.minY, original.minY, accuracy: 0.001)
    }

    func testPetDesktopFrameStaysInsideVisibleScreen() {
        let visibleFrame = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let panelSize = CGSize(width: 180, height: 188)
        let placement = PetDesktopPlacement(
            screenID: "external",
            normalizedX: 1,
            normalizedY: 0
        )

        let frame = PetDesktopPlacementCalculator.frame(
            for: placement,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertEqual(frame.minY, visibleFrame.minY)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testQuickPromptPrefersPetRightSideWhenSpaceAllows() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let petFrame = CGRect(x: 420, y: 320, width: 180, height: 188)
        let panelSize = CGSize(width: 360, height: 66)

        let frame = PetQuickPromptLayout.frame(
            anchorFrame: petFrame,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.minX, petFrame.maxX + PetQuickPromptLayout.horizontalGap)
        XCTAssertEqual(frame.midY, petFrame.midY, accuracy: 0.001)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testQuickPromptMovesToPetLeftSideNearRightEdge() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let petFrame = CGRect(x: 1_250, y: 320, width: 180, height: 188)
        let panelSize = CGSize(width: 360, height: 154)

        let frame = PetQuickPromptLayout.frame(
            anchorFrame: petFrame,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxX, petFrame.minX - PetQuickPromptLayout.horizontalGap)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testQuickPromptIsClampedInsideVerticalScreenBounds() {
        let visibleFrame = CGRect(x: 100, y: 40, width: 1_200, height: 760)
        let petFrame = CGRect(x: 500, y: 740, width: 180, height: 188)
        let panelSize = CGSize(width: 360, height: 154)

        let frame = PetQuickPromptLayout.frame(
            anchorFrame: petFrame,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.maxY, visibleFrame.maxY)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testQuickPromptOnlyExpandsWhenFeedbackExists() {
        XCTAssertEqual(
            PetQuickPromptLayout.preferredSize(
                isGenerating: false,
                reply: nil,
                errorMessage: nil
            ).height,
            66
        )
        XCTAssertEqual(
            PetQuickPromptLayout.preferredSize(
                isGenerating: true,
                reply: nil,
                errorMessage: nil
            ).height,
            154
        )
        XCTAssertEqual(
            PetQuickPromptLayout.preferredSize(
                isGenerating: false,
                reply: "你好呀",
                errorMessage: nil
            ).height,
            154
        )
    }
}
