import AppKit
import Combine
import CoreGraphics

enum IslandDisplayMode: Equatable {
    case physicalNotch
    case floatingCapsule
}

struct DisplayDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let isBuiltIn: Bool
    let hasNotch: Bool
    let isPrimary: Bool

    var detail: String {
        var labels: [String] = []
        if isBuiltIn { labels.append("内置") }
        if isPrimary { labels.append("主显示器") }
        labels.append(hasNotch ? "有刘海" : "浮动胶囊")
        return labels.joined(separator: " · ")
    }
}

enum DisplayTargetResolver {
    static func resolve(
        from displays: [DisplayDescriptor],
        mode: DisplayTargetMode,
        specificDisplayID: String?
    ) -> DisplayDescriptor? {
        guard let primary = displays.first(where: { $0.isPrimary }) ?? displays.first else {
            return nil
        }
        switch mode {
        case .builtIn:
            return displays.first(where: { $0.isBuiltIn }) ?? primary
        case .primary:
            return primary
        case .specific:
            return displays.first { $0.id == specificDisplayID } ?? primary
        }
    }
}

struct IslandScreenGeometry: Equatable {
    let screenID: String
    let screenName: String
    let frame: CGRect
    let notchRect: CGRect?
    let mode: IslandDisplayMode
    let directDisplayID: CGDirectDisplayID?
    let quartzFrame: CGRect?
    let fullScreenTopInset: CGFloat

    init(
        screenID: String,
        screenName: String,
        frame: CGRect,
        notchRect: CGRect?,
        mode: IslandDisplayMode,
        directDisplayID: CGDirectDisplayID? = nil,
        quartzFrame: CGRect? = nil,
        fullScreenTopInset: CGFloat = 0
    ) {
        self.screenID = screenID
        self.screenName = screenName
        self.frame = frame
        self.notchRect = notchRect
        self.mode = mode
        self.directDisplayID = directDisplayID
        self.quartzFrame = quartzFrame
        self.fullScreenTopInset = fullScreenTopInset
    }
}

struct IslandLayoutMetrics: Equatable {
    let size: CGSize
    let topOffset: CGFloat
    let cornerRadius: CGFloat
}

enum IslandLayoutCalculator {
    static func metrics(
        for presentation: IslandPresentation,
        geometry: IslandScreenGeometry,
        externalTopOffset: CGFloat = 6,
        floatingWidthAdjustment: CGFloat = 0
    ) -> IslandLayoutMetrics {
        let notchWidth = geometry.notchRect?.width ?? 0
        let notchHeight = geometry.notchRect?.height ?? 0
        let physical = geometry.mode == .physicalNotch

        let baseSize: CGSize
        switch presentation {
        case .silent:
            baseSize = physical
                ? CGSize(width: notchWidth + 24, height: notchHeight + 7)
                : CGSize(width: 230, height: 37)
        case .compact:
            baseSize = physical
                ? CGSize(width: notchWidth + 120, height: notchHeight + 7)
                : CGSize(width: 300, height: 48)
        case .temporaryHUD:
            baseSize = physical
                ? CGSize(width: notchWidth + 140, height: notchHeight + 7)
                : CGSize(width: 300, height: 52)
        case .hoverPreview:
            baseSize = physical
                ? CGSize(width: notchWidth + 120, height: notchHeight + 7)
                : CGSize(width: 280, height: 52)
        case .expanded:
            baseSize = physical
                ? CGSize(width: notchWidth + 152, height: notchHeight + 7)
                : CGSize(width: 320, height: 52)
        case .fileReceiving:
            baseSize = physical
                ? CGSize(width: notchWidth + 180, height: notchHeight + 7)
                : CGSize(width: 340, height: 52)
        }

        let size = physical
            ? baseSize
            : CGSize(
                width: max(180, baseSize.width + min(max(floatingWidthAdjustment, -40), 80)),
                height: baseSize.height
            )
        let topOffset: CGFloat = physical ? 0 : min(max(externalTopOffset, 0), 40)
        let radius: CGFloat
        switch presentation {
        case .silent, .compact: radius = physical ? 17 : size.height / 2
        case .temporaryHUD, .fileReceiving: radius = physical ? 18 : size.height / 2
        case .hoverPreview: radius = physical ? 17 : size.height / 2
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

enum FullScreenFrameMatcher {
    static func matches(
        windowBounds: CGRect,
        displayBounds: CGRect,
        allowedTopInset: CGFloat = 0,
        tolerance: CGFloat = 3
    ) -> Bool {
        let matchesFullDisplay = abs(windowBounds.minX - displayBounds.minX) <= tolerance &&
            abs(windowBounds.minY - displayBounds.minY) <= tolerance &&
            abs(windowBounds.width - displayBounds.width) <= tolerance &&
            abs(windowBounds.height - displayBounds.height) <= tolerance
        if matchesFullDisplay { return true }

        // macOS can keep the menu bar visible in a genuine full-screen Space.
        // In that mode the app fills the entire display except the reserved top strip.
        guard allowedTopInset > 0 else { return false }
        return abs(windowBounds.minX - displayBounds.minX) <= tolerance &&
            abs(windowBounds.minY - (displayBounds.minY + allowedTopInset)) <= tolerance &&
            abs(windowBounds.width - displayBounds.width) <= tolerance &&
            abs(windowBounds.maxY - displayBounds.maxY) <= tolerance
    }
}

enum PanelVisibilityPolicy {
    static func shouldShow(
        runtimeRequestedVisible: Bool,
        isTargetScreenFullscreen: Bool,
        behavior: FullScreenBehavior,
        state: IslandState
    ) -> Bool {
        guard runtimeRequestedVisible else { return false }
        guard isTargetScreenFullscreen else { return true }

        switch behavior {
        case .alwaysShow:
            return true
        case .hidden:
            return false
        case .importantOnly:
            if state.presentation == .fileReceiving { return true }
            return state.activity.map {
                $0.kind == .criticalSystem || $0.kind == .ringingTimer
            } ?? false
        }
    }
}

@MainActor
final class ScreenGeometryService: ObservableObject {
    @Published private(set) var availableDisplays: [DisplayDescriptor] = []

    init() {
        refreshAvailableDisplays()
    }

    func refreshAvailableDisplays() {
        let screens = NSScreen.screens
        availableDisplays = screens.enumerated().map { index, screen in
            descriptor(for: screen, isPrimary: index == 0)
        }
    }

    func current(
        mode: DisplayTargetMode = .builtIn,
        specificDisplayID: String? = nil
    ) -> IslandScreenGeometry? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let descriptors = screens.enumerated().map { index, screen in
            descriptor(for: screen, isPrimary: index == 0)
        }
        guard let target = DisplayTargetResolver.resolve(
            from: descriptors,
            mode: mode,
            specificDisplayID: specificDisplayID
        ), let targetIndex = descriptors.firstIndex(where: { $0.id == target.id })
        else { return nil }
        return geometry(for: screens[targetIndex])
    }

    func geometry(for screen: NSScreen) -> IslandScreenGeometry {
        let notchRect = notchRect(for: screen)
        let displayID = directDisplayID(for: screen)
        return IslandScreenGeometry(
            screenID: stableIdentifier(for: displayID) ?? screen.localizedName,
            screenName: screen.localizedName,
            frame: screen.frame,
            notchRect: notchRect,
            mode: notchRect == nil ? .floatingCapsule : .physicalNotch,
            directDisplayID: displayID,
            quartzFrame: displayID.map(CGDisplayBounds),
            fullScreenTopInset: max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        )
    }

    func isFullscreen(on geometry: IslandScreenGeometry) -> Bool {
        guard let targetBounds = geometry.quartzFrame,
              let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]]
        else { return false }

        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontmostPID,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds)
            else { return false }
            return FullScreenFrameMatcher.matches(
                windowBounds: bounds,
                displayBounds: targetBounds,
                allowedTopInset: geometry.fullScreenTopInset
            )
        }
    }

    private func descriptor(for screen: NSScreen, isPrimary: Bool) -> DisplayDescriptor {
        let displayID = directDisplayID(for: screen)
        let notch = notchRect(for: screen)
        return DisplayDescriptor(
            id: stableIdentifier(for: displayID) ?? screen.localizedName,
            name: screen.localizedName,
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
            hasNotch: notch != nil,
            isPrimary: isPrimary
        )
    }

    private func notchRect(for screen: NSScreen) -> CGRect? {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        guard screen.safeAreaInsets.top > 0,
              let left,
              let right,
              right.minX > left.maxX
        else { return nil }
        return CGRect(
            x: left.maxX,
            y: screen.frame.maxY - screen.safeAreaInsets.top,
            width: right.minX - left.maxX,
            height: screen.safeAreaInsets.top
        )
    }

    private func directDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func stableIdentifier(for displayID: CGDirectDisplayID?) -> String? {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let value = CFUUIDCreateString(nil, uuid)
        else { return nil }
        return value as String
    }
}
