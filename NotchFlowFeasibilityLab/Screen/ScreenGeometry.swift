import AppKit

struct ScreenGeometrySnapshot: Identifiable {
    let id: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let leftAuxiliaryArea: CGRect?
    let rightAuxiliaryArea: CGRect?
    let notchRect: CGRect?
    let hasPhysicalNotch: Bool

    var modeDescription: String {
        hasPhysicalNotch ? "物理刘海模式" : "无刘海回退模式"
    }

    var evidenceLines: [String] {
        [
            "屏幕：\(name)",
            "分辨率点：\(Int(frame.width)) × \(Int(frame.height))",
            "顶部安全区：\(Int(safeAreaInsets.top)) pt",
            "左辅助区：\(leftAuxiliaryArea.map(Self.describe) ?? "无")",
            "右辅助区：\(rightAuxiliaryArea.map(Self.describe) ?? "无")",
            "推导刘海区域：\(notchRect.map(Self.describe) ?? "无")",
            "判定：\(modeDescription)"
        ]
    }

    private static func describe(_ rect: CGRect) -> String {
        "x=\(Int(rect.minX)), y=\(Int(rect.minY)), w=\(Int(rect.width)), h=\(Int(rect.height))"
    }
}

enum ScreenGeometryCalculator {
    static func notchRect(
        screenFrame: CGRect,
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?,
        topSafeInset: CGFloat
    ) -> CGRect? {
        guard
            topSafeInset > 0,
            let leftAuxiliaryArea,
            let rightAuxiliaryArea,
            rightAuxiliaryArea.minX > leftAuxiliaryArea.maxX
        else {
            return nil
        }

        return CGRect(
            x: leftAuxiliaryArea.maxX,
            y: screenFrame.maxY - topSafeInset,
            width: rightAuxiliaryArea.minX - leftAuxiliaryArea.maxX,
            height: topSafeInset
        )
    }
}

@MainActor
enum ScreenGeometryProbe {
    static func snapshots() -> [ScreenGeometrySnapshot] {
        NSScreen.screens.map(snapshot(for:))
    }

    static func preferredScreen() -> NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    static func snapshot(for screen: NSScreen) -> ScreenGeometrySnapshot {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notch = ScreenGeometryCalculator.notchRect(
            screenFrame: screen.frame,
            leftAuxiliaryArea: left,
            rightAuxiliaryArea: right,
            topSafeInset: screen.safeAreaInsets.top
        )

        return ScreenGeometrySnapshot(
            id: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                .map(String.init(describing:)) ?? screen.localizedName,
            name: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            leftAuxiliaryArea: left,
            rightAuxiliaryArea: right,
            notchRect: notch,
            hasPhysicalNotch: notch != nil
        )
    }
}
