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

    func testExpandedPhysicalIslandStaysInsideCompactTopBand() {
        let metrics = IslandLayoutCalculator.metrics(for: .expanded, geometry: notchedScreen)
        XCTAssertEqual(metrics.size.width, notchedScreen.notchRect!.width + 152)
        XCTAssertEqual(metrics.size.height, notchedScreen.notchRect!.height + 7)
        XCTAssertEqual(metrics.topOffset, 0)
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
}
