import AppKit

enum IslandDisplayMode: Equatable {
    case physicalNotch
    case floatingCapsule
}

struct IslandScreenGeometry: Equatable {
    let screenID: String
    let screenName: String
    let frame: CGRect
    let notchRect: CGRect?
    let mode: IslandDisplayMode
}

struct IslandLayoutMetrics: Equatable {
    let size: CGSize
    let topOffset: CGFloat
    let cornerRadius: CGFloat
}

enum IslandLayoutCalculator {
    static func metrics(for presentation: IslandPresentation, geometry: IslandScreenGeometry) -> IslandLayoutMetrics {
        let notchWidth = geometry.notchRect?.width ?? 0
        let notchHeight = geometry.notchRect?.height ?? 0
        let physical = geometry.mode == .physicalNotch

        let size: CGSize
        switch presentation {
        case .silent:
            size = physical
                ? CGSize(width: notchWidth + 24, height: notchHeight + 7)
                : CGSize(width: 230, height: 37)
        case .compact:
            size = physical
                ? CGSize(width: notchWidth + 120, height: notchHeight + 7)
                : CGSize(width: 300, height: 48)
        case .temporaryHUD:
            size = physical
                ? CGSize(width: notchWidth + 140, height: notchHeight + 7)
                : CGSize(width: 300, height: 52)
        case .hoverPreview:
            size = physical
                ? CGSize(width: notchWidth + 116, height: notchHeight + 7)
                : CGSize(width: 280, height: 52)
        case .expanded:
            size = physical
                ? CGSize(width: notchWidth + 152, height: notchHeight + 7)
                : CGSize(width: 320, height: 52)
        case .fileReceiving:
            size = physical
                ? CGSize(width: notchWidth + 180, height: notchHeight + 7)
                : CGSize(width: 340, height: 52)
        }

        let topOffset: CGFloat = physical ? 0 : 6
        let radius: CGFloat
        switch presentation {
        case .silent, .compact: radius = physical ? 17 : size.height / 2
        case .temporaryHUD, .fileReceiving: radius = physical ? 18 : size.height / 2
        case .hoverPreview: radius = physical ? 18 : size.height / 2
        case .expanded: radius = physical ? 18 : size.height / 2
        }
        return IslandLayoutMetrics(size: size, topOffset: topOffset, cornerRadius: radius)
    }

    static func frame(for metrics: IslandLayoutMetrics, on screen: IslandScreenGeometry) -> CGRect {
        CGRect(
            x: screen.frame.midX - metrics.size.width / 2,
            y: screen.frame.maxY - metrics.topOffset - metrics.size.height,
            width: metrics.size.width,
            height: metrics.size.height
        )
    }
}

@MainActor
final class ScreenGeometryService {
    func current() -> IslandScreenGeometry? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return geometry(for: screen)
    }

    func geometry(for screen: NSScreen) -> IslandScreenGeometry {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchRect: CGRect?
        if screen.safeAreaInsets.top > 0,
           let left,
           let right,
           right.minX > left.maxX {
            notchRect = CGRect(
                x: left.maxX,
                y: screen.frame.maxY - screen.safeAreaInsets.top,
                width: right.minX - left.maxX,
                height: screen.safeAreaInsets.top
            )
        } else {
            notchRect = nil
        }

        return IslandScreenGeometry(
            screenID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                .map(String.init(describing:)) ?? screen.localizedName,
            screenName: screen.localizedName,
            frame: screen.frame,
            notchRect: notchRect,
            mode: notchRect == nil ? .floatingCapsule : .physicalNotch
        )
    }
}
