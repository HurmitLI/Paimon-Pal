import CoreGraphics
import XCTest
@testable import NotchFlowFeasibilityLab

final class ScreenGeometryCalculatorTests: XCTestCase {
    func testNotchRectIsDerivedFromAuxiliaryAreas() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 948, width: 645, height: 34)
        let right = CGRect(x: 867, y: 948, width: 645, height: 34)

        let result = ScreenGeometryCalculator.notchRect(
            screenFrame: screen,
            leftAuxiliaryArea: left,
            rightAuxiliaryArea: right,
            topSafeInset: 34
        )

        XCTAssertEqual(result, CGRect(x: 645, y: 948, width: 222, height: 34))
    }

    func testNoNotchFallsBackWhenAuxiliaryAreasAreMissing() {
        let result = ScreenGeometryCalculator.notchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            leftAuxiliaryArea: nil,
            rightAuxiliaryArea: nil,
            topSafeInset: 0
        )

        XCTAssertNil(result)
    }

    func testInvalidAuxiliaryOrderingDoesNotCreateNegativeNotch() {
        let result = ScreenGeometryCalculator.notchRect(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            leftAuxiliaryArea: CGRect(x: 0, y: 948, width: 900, height: 34),
            rightAuxiliaryArea: CGRect(x: 800, y: 948, width: 712, height: 34),
            topSafeInset: 34
        )

        XCTAssertNil(result)
    }
}
