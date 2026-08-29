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
}
