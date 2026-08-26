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
    private let preferences: AppPreferences
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var pointerWasInside = false
    private var runtimeRequestedVisible = false
    private var spaceReconcileTask: Task<Void, Never>?
    private var utilityWindowController: UtilityWindowController?
    private var onOpenSettings: (() -> Void)?

    init(
        coordinator: ActivityCoordinator,
        motion: MotionPreferences,
        screenService: ScreenGeometryService,
        music: MusicController,
        fileShelf: FileShelfController,
        systemStatus: SystemStatusController,
        timer: TimerController,
        preferences: AppPreferences,
        onOpenSettings: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.motion = motion
        self.screenService = screenService
        self.music = music
        self.fileShelf = fileShelf
        self.systemStatus = systemStatus
        self.timer = timer
        self.preferences = preferences
        self.onOpenSettings = onOpenSettings
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
        runtimeRequestedVisible = true
        screenService.refreshAvailableDisplays()
        reconcileVisibility(animated: false)
        // Launch Services may still be handing focus back to the previous app here.
        // Recheck after the foreground window and active Space have settled.
        scheduleSpaceReconciliation()
    }

    func hide() {
        runtimeRequestedVisible = false
        pointerWasInside = false
        coordinator.collapse()
        panel.orderOut(nil)
    }

    var isExpanded: Bool {
        coordinator.state.presentation == .expanded
    }

    func toggleExpanded() {
        guard panel.isVisible else { return }
        coordinator.toggleExpanded()
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
            preferences: preferences,
            onOpenUtilityWindow: { [weak self] section in self?.openUtilityWindow(section) },
            onOpenSettings: { [weak self] in self?.onOpenSettings?() }
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
                self?.reconcileVisibility(animated: false)
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
            .sink { [weak self] _ in
                self?.screenService.refreshAvailableDisplays()
                self?.reconcileVisibility(animated: false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.scheduleSpaceReconciliation() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in self?.scheduleSpaceReconciliation() }
            .store(in: &cancellables)

        preferences.$displayTargetMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reconcileVisibility(animated: false) }
            .store(in: &cancellables)
        preferences.$specificDisplayID
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reconcileVisibility(animated: false) }
            .store(in: &cancellables)
        preferences.$fullScreenBehavior
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reconcileVisibility(animated: false) }
            .store(in: &cancellables)
        preferences.$externalDisplayTopOffset
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reconcileVisibility(animated: false) }
            .store(in: &cancellables)
        preferences.$floatingCapsuleWidthAdjustment
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.reconcileVisibility(animated: false) }
            .store(in: &cancellables)
    }

    private func scheduleSpaceReconciliation() {
        spaceReconcileTask?.cancel()
        spaceReconcileTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.reconcileVisibility(animated: false)
        }
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
        guard panel.isVisible else {
            pointerWasInside = false
            return
        }
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
                timer: timer,
                preferences: preferences
            )
        }
        utilityWindowController?.show(section: section)
        coordinator.collapse()
    }

    private func updateFrame(
        for presentation: IslandPresentation? = nil,
        animated: Bool
    ) {
        guard let screen = screenService.current(
            mode: preferences.displayTargetMode,
            specificDisplayID: preferences.specificDisplayID
        ) else { return }
        let resolvedPresentation = presentation ?? coordinator.state.presentation
        let metrics = IslandLayoutCalculator.metrics(
            for: resolvedPresentation,
            geometry: screen,
            externalTopOffset: CGFloat(preferences.externalDisplayTopOffset),
            floatingWidthAdjustment: CGFloat(preferences.floatingCapsuleWidthAdjustment)
        )
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

    private func reconcileVisibility(animated: Bool) {
        guard let screen = screenService.current(
            mode: preferences.displayTargetMode,
            specificDisplayID: preferences.specificDisplayID
        ) else {
            panel.orderOut(nil)
            return
        }
        let shouldShow = PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: runtimeRequestedVisible,
            isTargetScreenFullscreen: screenService.isFullscreen(on: screen),
            behavior: preferences.fullScreenBehavior,
            state: coordinator.state
        )

        guard shouldShow else {
            pointerWasInside = false
            if coordinator.state.presentation == .expanded ||
                coordinator.state.presentation == .hoverPreview {
                coordinator.collapse()
            }
            panel.orderOut(nil)
            return
        }

        updateFrame(animated: animated)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        reconcilePointerLocation()
    }
}
