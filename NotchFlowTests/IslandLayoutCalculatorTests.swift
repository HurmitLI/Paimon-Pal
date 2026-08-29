import AppKit
import CoreGraphics
import XCTest
@testable import NotchFlow

final class IslandLayoutCalculatorTests: XCTestCase {
    func testSingleInstanceLockRejectsSecondOwnerAndRecoversAfterRelease() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let lockURL = directory.appendingPathComponent("running.lock")

        var firstOwner: SingleInstanceLock? = try XCTUnwrap(
            SingleInstanceLock.acquire(at: lockURL)
        )
        withExtendedLifetime(firstOwner) {
            XCTAssertNil(SingleInstanceLock.acquire(at: lockURL))
        }

        firstOwner = nil
        XCTAssertNotNil(SingleInstanceLock.acquire(at: lockURL))
    }

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

    func testPetAnimationCompositesAtThirtyFramesPerSecond() {
        XCTAssertEqual(NotchPetMotion.displayFramesPerSecond, 30)
        XCTAssertLessThan(NotchPetMotion.idle.crossfadeDuration, 0.1)
        XCTAssertGreaterThan(NotchPetMotion.listening.crossfadeDuration, 0)
    }

    func testIdleChoreographyAddsAQuietGreetingWave() {
        XCTAssertNil(NotchPetIdleChoreography.flourish(afterCompletedCycles: 1))
        XCTAssertEqual(
            NotchPetIdleChoreography.flourish(afterCompletedCycles: 2),
            .clickReaction
        )
        XCTAssertNil(NotchPetIdleChoreography.flourish(afterCompletedCycles: 3))
    }

    func testIdleAndListeningMotionsShareCanvasHeightAndFootAnchor() throws {
        let motions: [NotchPetMotion] = [.idle, .listening]
        var contentHeights: [CGFloat] = []
        var bottomAnchors: [CGFloat] = []

        for motion in motions {
            let images = try NotchPetAssetLoader().frames(for: motion)
            let frames = try images.map { image in
                var proposedRect = CGRect(origin: .zero, size: image.size)
                guard let frame = image.cgImage(
                    forProposedRect: &proposedRect,
                    context: nil,
                    hints: nil
                ) else {
                    throw XCTSkip("无法读取 \(motion.rawValue) 的 CGImage")
                }
                return frame
            }
            let measuredBounds = frames.compactMap(NotchPetFrameNormalizer.contentBounds)
            guard let contentHeight = NotchPetFrameNormalizer.median(
                measuredBounds.map(\.height)
            ), let bottomAnchor = measuredBounds.map({
                NotchPetFrameNormalizer.canvasSize.height - $0.maxY
            }).min() else {
                XCTFail("\(motion.rawValue) 没有可见角色像素")
                continue
            }

            XCTAssertTrue(frames.allSatisfy {
                $0.width == Int(NotchPetFrameNormalizer.canvasSize.width) &&
                    $0.height == Int(NotchPetFrameNormalizer.canvasSize.height)
            })
            contentHeights.append(contentHeight)
            bottomAnchors.append(bottomAnchor)
        }

        XCTAssertLessThanOrEqual(
            (contentHeights.max() ?? 0) - (contentHeights.min() ?? 0),
            3
        )
        XCTAssertLessThanOrEqual(
            (bottomAnchors.max() ?? 0) - (bottomAnchors.min() ?? 0),
            2
        )
    }

    func testStableBodyStagesUseOneVerticalOffset() {
        let stages: [NotchPetStage] = [
            .idle, .reacting, .listening, .speaking, .celebrating
        ]
        let offsets = Set(stages.map(NotchPetPresentationMetrics.verticalOffset))

        XCTAssertEqual(offsets, [18])
    }

    func testEveryFullBodyMotionUsesStableCanvasNormalization() {
        let expected: Set<NotchPetMotion> = [
            .idle, .clickReaction, .listening, .speaking, .successCelebration
        ]

        XCTAssertEqual(
            Set(NotchPetMotion.allCases.filter(\.usesStableBodyCanvas)),
            expected
        )
    }

    func testTransitionMotionsUseEndpointCalibrations() {
        XCTAssertEqual(
            NotchPetMotion.sleepToPeek.transitionCalibration,
            .init(referenceFrameIndex: 7, targetContentHeight: 207, bottomInset: 77)
        )
        XCTAssertEqual(
            NotchPetMotion.peekToEmerge.transitionCalibration,
            .init(referenceFrameIndex: 7, targetContentHeight: 332, bottomInset: 24)
        )
        XCTAssertEqual(
            NotchPetMotion.returnToSleep.transitionCalibration,
            .init(referenceFrameIndex: 0, targetContentHeight: 332, bottomInset: 24)
        )
        XCTAssertEqual(
            NotchPetMotion.sleepToPeek.transitionZoomCompensation,
            Array(repeating: 0.80, count: 8)
        )
        XCTAssertEqual(
            NotchPetMotion.peekToEmerge.transitionZoomCompensation,
            [0.80, 0.86, 0.88, 0.89, 0.89, 0.92, 0.97, 1.00]
        )
        XCTAssertNil(NotchPetMotion.returnToSleep.transitionZoomCompensation)
    }

    func testTransitionEndpointsMatchAdjacentAnimationSizeAndAnchor() throws {
        let sleepLast = try petFrameMetrics(for: .sleepToPeek, frameIndex: 7)
        let emergeFirst = try petFrameMetrics(for: .peekToEmerge, frameIndex: 0)
        let emergeLast = try petFrameMetrics(for: .peekToEmerge, frameIndex: 7)
        let idleFirst = try petFrameMetrics(for: .idle, frameIndex: 0)
        let returnFirst = try petFrameMetrics(for: .returnToSleep, frameIndex: 0)

        XCTAssertEqual(sleepLast.height, emergeFirst.height, accuracy: 3)
        XCTAssertEqual(sleepLast.bottomInset, emergeFirst.bottomInset, accuracy: 3)
        XCTAssertEqual(emergeLast.height, idleFirst.height, accuracy: 3)
        XCTAssertEqual(emergeLast.bottomInset, idleFirst.bottomInset, accuracy: 2)
        XCTAssertEqual(returnFirst.height, idleFirst.height, accuracy: 3)
        XCTAssertEqual(returnFirst.bottomInset, idleFirst.bottomInset, accuracy: 2)
    }

    func testFrameNormalizerUnifiesDifferentSourceCanvasRatios() throws {
        let square = try makeOpaqueFrame(
            size: CGSize(width: 100, height: 100),
            contentRect: CGRect(x: 24, y: 12, width: 52, height: 62)
        )
        let portrait = try makeOpaqueFrame(
            size: CGSize(width: 80, height: 120),
            contentRect: CGRect(x: 18, y: 22, width: 44, height: 82)
        )
        let squareResult = try XCTUnwrap(
            NotchPetFrameNormalizer.normalizing([square]).first
        )
        let portraitResult = try XCTUnwrap(
            NotchPetFrameNormalizer.normalizing([portrait]).first
        )
        let squareBounds = try XCTUnwrap(
            NotchPetFrameNormalizer.contentBounds(in: squareResult)
        )
        let portraitBounds = try XCTUnwrap(
            NotchPetFrameNormalizer.contentBounds(in: portraitResult)
        )

        XCTAssertEqual(squareBounds.height, portraitBounds.height, accuracy: 2)
        XCTAssertEqual(
            NotchPetFrameNormalizer.canvasSize.height - squareBounds.maxY,
            NotchPetFrameNormalizer.canvasSize.height - portraitBounds.maxY,
            accuracy: 2
        )
    }

    func testTransitionZoomCompensationPreservesBottomAnchor() throws {
        let frame = try makeOpaqueFrame(
            size: CGSize(width: 100, height: 100),
            contentRect: CGRect(x: 20, y: 10, width: 60, height: 70)
        )
        let originalBounds = try XCTUnwrap(
            NotchPetFrameNormalizer.contentBounds(in: frame)
        )
        let result = try XCTUnwrap(
            NotchPetFrameNormalizer.compensatingTransitionZoom(
                [frame],
                scaleFactors: [0.8]
            ).first
        )
        let resultBounds = try XCTUnwrap(
            NotchPetFrameNormalizer.contentBounds(in: result)
        )

        XCTAssertEqual(resultBounds.width, originalBounds.width * 0.8, accuracy: 2)
        XCTAssertEqual(resultBounds.height, originalBounds.height * 0.8, accuracy: 2)
        XCTAssertEqual(
            CGFloat(result.height) - resultBounds.maxY,
            CGFloat(frame.height) - originalBounds.maxY,
            accuracy: 1
        )
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
        XCTAssertEqual(hover.horizontalOffset, compact.horizontalOffset)
        XCTAssertEqual(hover.cornerRadius, compact.cornerRadius)
        XCTAssertEqual(hover.size.height, notchedScreen.notchRect!.height + 7)
    }

    func testPhysicalActivityStatesLeaveRightMenuBarSafetySpace() {
        for presentation in [
            IslandPresentation.compact,
            .hoverPreview,
            .expanded,
            .fileReceiving
        ] {
            let metrics = IslandLayoutCalculator.metrics(
                for: presentation,
                geometry: notchedScreen
            )
            let frame = IslandLayoutCalculator.frame(for: metrics, on: notchedScreen)
            let centeredRightEdge = notchedScreen.frame.midX + metrics.size.width / 2

            XCTAssertEqual(metrics.horizontalOffset, -12)
            XCTAssertEqual(frame.maxX, centeredRightEdge - 12)
            XCTAssertTrue(frame.contains(notchedScreen.notchRect!))
        }

        XCTAssertEqual(
            IslandLayoutCalculator.metrics(for: .silent, geometry: notchedScreen)
                .horizontalOffset,
            0
        )
        XCTAssertEqual(
            IslandLayoutCalculator.metrics(for: .temporaryHUD, geometry: notchedScreen)
                .horizontalOffset,
            0
        )
    }

    func testFloatingCapsuleRemainsCentered() {
        let external = IslandScreenGeometry(
            screenID: "external",
            screenName: "External",
            frame: CGRect(x: 100, y: 40, width: 1_920, height: 1_080),
            notchRect: nil,
            mode: .floatingCapsule
        )

        for presentation in IslandPresentation.allCases {
            let metrics = IslandLayoutCalculator.metrics(for: presentation, geometry: external)
            let frame = IslandLayoutCalculator.frame(for: metrics, on: external)
            XCTAssertEqual(metrics.horizontalOffset, 0)
            XCTAssertEqual(frame.midX, external.frame.midX)
        }
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

    private func makeOpaqueFrame(size: CGSize, contentRect: CGRect) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(contentRect)
        return try XCTUnwrap(context.makeImage())
    }

    private func petFrameMetrics(
        for motion: NotchPetMotion,
        frameIndex: Int
    ) throws -> (height: CGFloat, bottomInset: CGFloat) {
        let frames = try NotchPetAssetLoader().frames(for: motion)
        guard frames.indices.contains(frameIndex) else {
            throw XCTSkip("\(motion.rawValue) 缺少第 \(frameIndex + 1) 帧")
        }
        var proposedRect = CGRect(origin: .zero, size: frames[frameIndex].size)
        let frame = try XCTUnwrap(frames[frameIndex].cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ))
        let bounds = try XCTUnwrap(NotchPetFrameNormalizer.contentBounds(in: frame))
        return (
            bounds.height,
            NotchPetFrameNormalizer.canvasSize.height - bounds.maxY
        )
    }
}
