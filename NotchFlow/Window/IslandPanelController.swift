import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandPanelController {
    private let coordinator: ActivityCoordinator
    private let motion: MotionPreferences
    private let screenService: ScreenGeometryService
    private let music: MusicController
    private let fileShelf: FileShelfController
    private let systemStatus: SystemStatusController
    private let timer: TimerController
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var pointerWasInside = false
    private var utilityWindowController: UtilityWindowController?

    init(
        coordinator: ActivityCoordinator,
        motion: MotionPreferences,
        screenService: ScreenGeometryService,
        music: MusicController,
        fileShelf: FileShelfController,
        systemStatus: SystemStatusController,
        timer: TimerController
    ) {
        self.coordinator = coordinator
        self.motion = motion
        self.screenService = screenService
        self.music = music
        self.fileShelf = fileShelf
        self.systemStatus = systemStatus
        self.timer = timer
        panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        installContent()
        observeState()
        observeScreens()
        installPointerMonitor()
        installOutsideClickMonitor()
    }

    func show() {
        updateFrame(animated: false)
        panel.orderFrontRegardless()
        reconcilePointerLocation()
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
    }

    private func installContent() {
        let root = IslandRootView(
            coordinator: coordinator,
            motion: motion,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer,
            onOpenUtilityWindow: { [weak self] section in self?.openUtilityWindow(section) }
        )
        .ignoresSafeArea()
        let hostingView = IslandHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    private func observeState() {
        coordinator.$state
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                self?.updateFrame(for: state.presentation, animated: true)
            }
            .store(in: &cancellables)

        motion.$reduceMotion
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)
    }

    private func observeScreens() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.updateFrame(animated: false) }
            .store(in: &cancellables)
    }

    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            guard let self,
                  coordinator.state.presentation == .expanded
            else { return }
            // Global monitor events do not provide reliable window-local coordinates.
            // Compare the current pointer in AppKit screen coordinates with the panel frame.
            if !panel.frame.contains(NSEvent.mouseLocation) {
                coordinator.collapse()
            }
        }
    }

    private func installPointerMonitor() {
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in self?.reconcilePointerLocation()
        }
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
            [weak self] event in
            self?.reconcilePointerLocation()
            return event
        }
    }

    private func reconcilePointerLocation() {
        let isInside = panel.frame.contains(NSEvent.mouseLocation)
        guard isInside != pointerWasInside else { return }
        pointerWasInside = isInside

        if isInside {
            coordinator.pointerEntered()
        } else {
            coordinator.pointerExited { [weak self] in
                guard let self else { return true }
                return !panel.frame.contains(NSEvent.mouseLocation)
            }
        }
    }

    private func openUtilityWindow(_ section: UtilitySection) {
        if utilityWindowController == nil {
            utilityWindowController = UtilityWindowController(
                music: music,
                fileShelf: fileShelf,
                systemStatus: systemStatus,
                timer: timer
            )
        }
        utilityWindowController?.show(section: section)
        coordinator.collapse()
    }

    private func updateFrame(
        for presentation: IslandPresentation? = nil,
        animated: Bool
    ) {
        guard let screen = screenService.current() else { return }
        let resolvedPresentation = presentation ?? coordinator.state.presentation
        let metrics = IslandLayoutCalculator.metrics(for: resolvedPresentation, geometry: screen)
        let targetFrame = IslandLayoutCalculator.frame(for: metrics, on: screen)

        guard animated, panel.isVisible else {
            panel.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.windowAnimationDuration
            context.timingFunction = motion.reduceMotion
                ? CAMediaTimingFunction(name: .easeInEaseOut)
                : CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.28, 1.0)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
}
