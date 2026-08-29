import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPetPanelController {
    private static let panelSize = CGSize(width: 180, height: 188)

    private let coordinator: ActivityCoordinator
    private let screenService: ScreenGeometryService
    private let preferences: AppPreferences
    private let pet: NotchPetController
    private let panel: IslandPanel
    private var runtimeRequestedVisible = false
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var localMouseDownMonitor: Any?
    private var retreatTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(
        coordinator: ActivityCoordinator,
        screenService: ScreenGeometryService,
        preferences: AppPreferences
    ) {
        self.coordinator = coordinator
        self.screenService = screenService
        self.preferences = preferences
        pet = NotchPetController()
        panel = IslandPanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        installContent()
        observeRuntime()
        installPointerMonitor()
    }

    func show() {
        runtimeRequestedVisible = true
        reconcileVisibility()
#if DEBUG
        // 只用于本地视觉回归，正常启动不会命中。
        if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_AUTOPLAY"] == "1" {
            pet.wakeUp()
        }
#endif
    }

    func hide() {
        runtimeRequestedVisible = false
        retreatTask?.cancel()
        pet.resetToSleep()
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.isMovable = false
        // 默认穿透鼠标；只有指针真正位于待机宠物身上时才临时接收点击。
        panel.ignoresMouseEvents = true
    }

    private func installContent() {
        let root = NotchPetView(pet: pet).ignoresSafeArea()
        let hostingView = IslandHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    private func observeRuntime() {
        coordinator.$state
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcileVisibility() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reconcileVisibility() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.reconcileVisibility() }
            .store(in: &cancellables)

        preferences.$displayTargetMode
            .combineLatest(preferences.$specificDisplayID)
            .sink { [weak self] _ in self?.reconcileVisibility() }
            .store(in: &cancellables)

        preferences.$fullScreenBehavior
            .sink { [weak self] _ in self?.reconcileVisibility() }
            .store(in: &cancellables)

        pet.$stage
            .removeDuplicates()
            .sink { [weak self] _ in self?.reconcilePointerLocation() }
            .store(in: &cancellables)
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
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self, event.window === panel,
                  pet.stage == .idle,
                  petHitFrame.contains(NSEvent.mouseLocation)
            else { return event }

            retreatTask?.cancel()
            pet.reactToClick()
            return nil
        }
    }

    private func reconcileVisibility() {
        guard runtimeRequestedVisible else { return hidePanel(reason: "runtime hidden") }
        guard preferences.hasCompletedOnboarding else { return hidePanel(reason: "onboarding") }
        guard !preferences.isPaused else { return hidePanel(reason: "paused") }
        guard pet.hasRenderableFrame else {
            return hidePanel(reason: pet.lastError ?? "missing frame")
        }
        guard stateAllowsPet else { return hidePanel(reason: "island activity") }
        guard let geometry = currentPhysicalNotchGeometry else {
            return hidePanel(reason: "no physical notch")
        }
        let isFullscreen = screenService.isFullscreen(on: geometry)
        guard PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: isFullscreen,
            behavior: preferences.fullScreenBehavior,
            state: coordinator.state
        ) else {
            return hidePanel(reason: "fullscreen policy")
        }

        panel.setFrame(panelFrame(on: geometry), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        reconcilePointerLocation()
    }

    private func hidePanel(reason: String) {
        retreatTask?.cancel()
        panel.ignoresMouseEvents = true
        pet.resetToSleep()
        panel.orderOut(nil)
    }

    private var stateAllowsPet: Bool {
        switch coordinator.state {
        case .silent:
            true
        case .hoverPreview(let activity):
            activity == nil
        case .compact, .temporaryHUD, .expanded, .fileReceiving:
            false
        }
    }

    private var currentPhysicalNotchGeometry: IslandScreenGeometry? {
        guard let geometry = screenService.current(
            mode: preferences.displayTargetMode,
            specificDisplayID: preferences.specificDisplayID
        ), geometry.mode == .physicalNotch, geometry.notchRect != nil else {
            return nil
        }
        return geometry
    }

    private func panelFrame(on geometry: IslandScreenGeometry) -> CGRect {
        CGRect(
            x: geometry.frame.midX - Self.panelSize.width / 2,
            y: geometry.frame.maxY - Self.panelSize.height,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )
    }

    private func reconcilePointerLocation() {
        guard panel.isVisible, let geometry = currentPhysicalNotchGeometry,
              let notchRect = geometry.notchRect else {
            panel.ignoresMouseEvents = true
            return
        }

        let pointer = NSEvent.mouseLocation
        panel.ignoresMouseEvents = !(pet.stage == .idle && petHitFrame.contains(pointer))
        let petInteractionFrame = panel.frame.insetBy(dx: 18, dy: 10)
        if notchRect.contains(pointer) || (pet.isAwake && petInteractionFrame.contains(pointer)) {
            retreatTask?.cancel()
            pet.wakeUp()
        } else if pet.isAwake {
            scheduleReturnToSleep()
        }
    }

    private var petHitFrame: CGRect {
        panel.frame.insetBy(dx: 24, dy: 12)
    }

    private func scheduleReturnToSleep() {
#if DEBUG
        if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_AUTOPLAY"] == "1" {
            return
        }
#endif
        retreatTask?.cancel()
        retreatTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled, let self else { return }
            let pointer = NSEvent.mouseLocation
            guard !panel.frame.insetBy(dx: 18, dy: 10).contains(pointer) else { return }
            pet.returnToSleep()
        }
    }
}
