import AppKit
import Combine
import SwiftUI

private final class NotchLabPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Borderless windows are normally pushed below the menu-bar safe area.
    // The notch experiment must be allowed to occupy the physical top edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class NonActivatingHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class LabPanelController: ObservableObject {
    enum Presentation: String {
        case collapsed = "收起"
        case expanded = "展开"
    }

    @Published private(set) var presentation: Presentation = .collapsed
    @Published private(set) var isVisible = false

    private var panel: NSPanel?

    func showCollapsed() {
        presentation = .collapsed
        show(size: preferredCollapsedSize())
    }

    func showExpanded() {
        presentation = .expanded
        show(size: CGSize(width: 420, height: 156))
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func preferredCollapsedSize() -> CGSize {
        guard let screen = ScreenGeometryProbe.preferredScreen() else {
            return CGSize(width: 220, height: 38)
        }
        let snapshot = ScreenGeometryProbe.snapshot(for: screen)
        guard let notchRect = snapshot.notchRect else {
            return CGSize(width: 220, height: 38)
        }
        return CGSize(
            width: notchRect.width + 72,
            height: notchRect.height + 10
        )
    }

    private func show(size: CGSize) {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateContent(of: panel)
        position(panel: panel, size: size)
        panel.orderFrontRegardless()
        isVisible = true
    }

    private func makePanel() -> NSPanel {
        let panel = NotchLabPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // `isFloatingPanel` resets the level to 3, so set the final level after it.
        // Level 26 is one step above the system menu/status-bar layer (25),
        // allowing the visible areas beside the physical notch to receive clicks.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func updateContent(of panel: NSPanel) {
        let content = LabPanelView(presentation: presentation) { [weak self] in
            guard let self else { return }
            if presentation == .collapsed {
                showExpanded()
            } else {
                showCollapsed()
            }
        }
        panel.contentView = NonActivatingHostingView(rootView: content.ignoresSafeArea())
    }

    private func position(panel: NSPanel, size: CGSize) {
        guard let screen = ScreenGeometryProbe.preferredScreen() else { return }
        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true, animate: isVisible)
    }
}

private struct LabPanelView: View {
    let presentation: LabPanelController.Presentation
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Group {
                if presentation == .collapsed {
                    HStack {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Spacer()
                        Circle().fill(.blue).frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                } else {
                    Text("NSPanel 展开状态 · 点击收起")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: presentation == .collapsed ? 12 : 24))
        }
        .buttonStyle(.plain)
    }
}
