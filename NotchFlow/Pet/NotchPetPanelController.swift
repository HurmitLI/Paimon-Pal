import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPetPanelController {
    private static let panelSize = CGSize(width: 180, height: 188)
    private static let dragThreshold: CGFloat = 6

    private let coordinator: ActivityCoordinator
    private let screenService: ScreenGeometryService
    private let preferences: AppPreferences
    private let pet: NotchPetController
    private let panel: IslandPanel
    private var runtimeRequestedVisible = false
    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var retreatTask: Task<Void, Never>?
    private var pointerDownLocation: CGPoint?
    private var dragStartPanelOrigin: CGPoint?
    private var isDraggingPet = false
    private var isDetached: Bool
    private var quickPromptAllowsDrag = false
    private var cancellables: Set<AnyCancellable> = []

    var onPetClicked: (() -> Void)?
    var onPresentationFrameChanged: (() -> Void)?
    var onPetDocked: (() -> Void)?

    var presentationFrame: CGRect {
        panel.frame
    }

    var presentationVisibleFrame: CGRect {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        return screen(containing: center)?.visibleFrame
            ?? panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
    }

    init(
        coordinator: ActivityCoordinator,
        screenService: ScreenGeometryService,
        preferences: AppPreferences
    ) {
        self.coordinator = coordinator
        self.screenService = screenService
        self.preferences = preferences
        isDetached = preferences.petDesktopPlacement != nil
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

    var isListening: Bool {
        pet.isListening
    }

    var isSpeaking: Bool {
        pet.isSpeaking
    }

    func toggleListeningForTesting() {
        retreatTask?.cancel()
        if pet.isListening {
            pet.stopListening()
        } else {
            pet.startListening()
        }
        reconcileVisibility()
    }

    func toggleSpeakingForTesting() {
        retreatTask?.cancel()
        if pet.isSpeaking {
            pet.stopSpeaking()
        } else {
            pet.startSpeaking()
        }
        reconcileVisibility()
    }

    func celebrateSuccessForTesting() {
        retreatTask?.cancel()
        pet.celebrateSuccess()
        reconcileVisibility()
    }

    func beginModelListening() {
        quickPromptAllowsDrag = false
        retreatTask?.cancel()
        pet.startListening()
        reconcileVisibility()
    }

    func beginQuickPromptListening() {
        quickPromptAllowsDrag = true
        retreatTask?.cancel()
        pet.startListening()
        reconcileVisibility()
    }

    func beginModelSpeaking() {
        quickPromptAllowsDrag = false
        retreatTask?.cancel()
        pet.startSpeaking()
        reconcileVisibility()
    }

    func endModelInteraction() {
        quickPromptAllowsDrag = false
        retreatTask?.cancel()
        pet.stopListening()
        pet.stopSpeaking()
        reconcileVisibility()
    }

    func finishModelInteractionSuccessfully() {
        quickPromptAllowsDrag = false
        retreatTask?.cancel()
        pet.celebrateSuccess()
        reconcileVisibility()
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
        let hostingView = NotchPetHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onMouseDown = { [weak self] event in
            self?.handlePetMouseDown(event)
        }
        hostingView.onMouseDragged = { [weak self] event in
            self?.handlePetMouseDragged(event)
        }
        hostingView.onMouseUp = { [weak self] event in
            self?.handlePetMouseUp(event)
        }
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
            .sink { [weak self] _ in self?.reconcileVisibility() }
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
    }

    private func reconcileVisibility() {
        guard runtimeRequestedVisible else { return hidePanel(reason: "runtime hidden") }
        guard preferences.hasCompletedOnboarding else { return hidePanel(reason: "onboarding") }
        guard !preferences.isPaused else { return hidePanel(reason: "paused") }
        guard pet.hasRenderableFrame else {
            return hidePanel(reason: pet.lastError ?? "missing frame")
        }
        guard NotchPetActivityVisibilityPolicy.allows(
            state: coordinator.state,
            petKeepsVisible: pet.keepsVisibleWithoutPointer || isDetached
        ) else {
            return hidePanel(reason: "island activity")
        }
        guard let geometry = currentPhysicalNotchGeometry else {
            return hidePanel(reason: "no physical notch")
        }
        let visibilityGeometry = detachedScreenGeometry ?? geometry
        let isFullscreen = screenService.isFullscreen(on: visibilityGeometry)
        guard PanelVisibilityPolicy.shouldShow(
            runtimeRequestedVisible: true,
            isTargetScreenFullscreen: isFullscreen,
            behavior: preferences.fullScreenBehavior,
            state: coordinator.state
        ) else {
            return hidePanel(reason: "fullscreen policy")
        }

        if isDetached, !pet.isAwake {
            pet.wakeUp()
        }
        let targetFrame: CGRect
        if isDraggingPet {
            targetFrame = panel.frame
        } else if isDetached, let detachedFrame = resolvedDetachedFrame() {
            targetFrame = detachedFrame
        } else {
            targetFrame = panelFrame(on: geometry)
        }
        // Stage changes do not move the panel. Re-applying an identical frame with
        // display=true briefly clears a transparent NSPanel before SwiftUI redraws,
        // which appears as a white flash over a light desktop background.
        if panel.frame != targetFrame {
            panel.setFrame(targetFrame, display: false)
            onPresentationFrameChanged?()
        }
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
        panel.ignoresMouseEvents = !(
            (pet.acceptsConversationClick || acceptsCurrentDesktopDrag) &&
                petHitFrame.contains(pointer)
        )
        if isDetached {
            retreatTask?.cancel()
            if !pet.isAwake {
                pet.wakeUp()
            }
            return
        }
        if pet.keepsVisibleWithoutPointer {
            retreatTask?.cancel()
            return
        }
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

    private var acceptsCurrentDesktopDrag: Bool {
        pet.acceptsDesktopDrag || (quickPromptAllowsDrag && pet.isListening)
    }

    private func handlePetMouseDown(_ event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        guard petHitFrame.contains(pointer),
              pet.acceptsConversationClick || acceptsCurrentDesktopDrag else { return }

        retreatTask?.cancel()
        pointerDownLocation = pointer
        dragStartPanelOrigin = acceptsCurrentDesktopDrag ? panel.frame.origin : nil
        isDraggingPet = false
    }

    private func handlePetMouseDragged(_ event: NSEvent) {
        guard let pointerDownLocation, let dragStartPanelOrigin else { return }
        let pointer = NSEvent.mouseLocation
        let delta = CGPoint(
            x: pointer.x - pointerDownLocation.x,
            y: pointer.y - pointerDownLocation.y
        )
        if !isDraggingPet {
            guard hypot(delta.x, delta.y) >= Self.dragThreshold else { return }
            isDraggingPet = true
            isDetached = true
        }

        let proposed = CGRect(
            origin: CGPoint(
                x: dragStartPanelOrigin.x + delta.x,
                y: dragStartPanelOrigin.y + delta.y
            ),
            size: Self.panelSize
        )
        let targetScreen = screen(containing: pointer) ?? panel.screen ?? NSScreen.main
        let constrained = PetDesktopPlacementCalculator.constrainedFrame(
            proposed,
            inside: targetScreen?.visibleFrame ?? proposed
        )
        panel.setFrame(constrained, display: false)
        onPresentationFrameChanged?()
    }

    private func handlePetMouseUp(_ event: NSEvent) {
        defer {
            pointerDownLocation = nil
            dragStartPanelOrigin = nil
            isDraggingPet = false
            reconcilePointerLocation()
        }

        guard pointerDownLocation != nil else { return }
        if isDraggingPet {
            if shouldDockToNotch {
                dockPetToNotch()
            } else {
                persistCurrentDesktopPlacement()
            }
            return
        }

        guard pet.acceptsConversationClick else { return }
        if let onPetClicked {
            onPetClicked()
        } else {
            pet.reactToClick()
        }
    }

    private var shouldDockToNotch: Bool {
        guard let geometry = currentPhysicalNotchGeometry else { return false }
        let home = panelFrame(on: geometry).insetBy(dx: -48, dy: -40)
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        return home.contains(center)
    }

    private func dockPetToNotch() {
        guard let geometry = currentPhysicalNotchGeometry else { return }
        isDetached = false
        preferences.clearPetDesktopPlacement()
        panel.setFrame(panelFrame(on: geometry), display: false)
        onPresentationFrameChanged?()
        onPetDocked?()
        pet.returnToSleepAfterDocking()
    }

    private func persistCurrentDesktopPlacement() {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let targetScreen = screen(containing: center) ?? panel.screen else { return }
        let screenID = screenService.geometry(for: targetScreen).screenID
        let placement = PetDesktopPlacementCalculator.placement(
            for: panel.frame,
            screenID: screenID,
            visibleFrame: targetScreen.visibleFrame
        )
        preferences.savePetDesktopPlacement(placement)
    }

    private var detachedScreenGeometry: IslandScreenGeometry? {
        guard isDetached, let placement = preferences.petDesktopPlacement,
              let targetScreen = NSScreen.screens.first(where: {
                  screenService.geometry(for: $0).screenID == placement.screenID
              }) else { return nil }
        return screenService.geometry(for: targetScreen)
    }

    private func resolvedDetachedFrame() -> CGRect? {
        guard let placement = preferences.petDesktopPlacement else { return nil }
        let targetScreen = NSScreen.screens.first(where: {
            screenService.geometry(for: $0).screenID == placement.screenID
        }) ?? NSScreen.main
        guard let targetScreen else { return nil }
        return PetDesktopPlacementCalculator.frame(
            for: placement,
            panelSize: Self.panelSize,
            visibleFrame: targetScreen.visibleFrame
        )
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
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
            guard !pet.keepsVisibleWithoutPointer else { return }
            let pointer = NSEvent.mouseLocation
            guard !panel.frame.insetBy(dx: 18, dy: 10).contains(pointer) else { return }
            pet.returnToSleep()
        }
    }
}

enum PetDesktopPlacementCalculator {
    static func placement(
        for panelFrame: CGRect,
        screenID: String,
        visibleFrame: CGRect
    ) -> PetDesktopPlacement {
        let x = visibleFrame.width > 0
            ? (panelFrame.midX - visibleFrame.minX) / visibleFrame.width
            : 0.5
        let y = visibleFrame.height > 0
            ? (panelFrame.midY - visibleFrame.minY) / visibleFrame.height
            : 0.5
        return PetDesktopPlacement(
            screenID: screenID,
            normalizedX: min(max(x, 0), 1),
            normalizedY: min(max(y, 0), 1)
        )
    }

    static func frame(
        for placement: PetDesktopPlacement,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let center = CGPoint(
            x: visibleFrame.minX + visibleFrame.width * placement.normalizedX,
            y: visibleFrame.minY + visibleFrame.height * placement.normalizedY
        )
        let proposed = CGRect(
            x: center.x - panelSize.width / 2,
            y: center.y - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        return constrainedFrame(proposed, inside: visibleFrame)
    }

    static func constrainedFrame(_ frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        guard visibleFrame.width >= frame.width, visibleFrame.height >= frame.height else {
            return CGRect(origin: visibleFrame.origin, size: frame.size)
        }
        return CGRect(
            x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width),
            y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }
}

private final class NotchPetHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }
}

enum NotchPetActivityVisibilityPolicy {
    static func allows(state: IslandState, petKeepsVisible: Bool) -> Bool {
        // 用户主动开启的聆听或说话状态必须持续，不能被普通活动打断。
        if petKeepsVisible {
            return true
        }

        return switch state {
        case .silent:
            true
        case .compact(let activity):
            activity.allowsPetCompanion
        case .hoverPreview(let activity):
            activity?.allowsPetCompanion ?? true
        case .temporaryHUD, .expanded, .fileReceiving:
            false
        }
    }
}

private extension IslandActivity {
    var allowsPetCompanion: Bool {
        kind == .timer || kind == .music
    }
}
