import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: IslandPanelController?
    private var musicController: MusicController?
    private var fileShelfController: FileShelfController?
    private var systemStatusController: SystemStatusController?
    private var timerController: TimerController?
    private var preferences: AppPreferences?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var statusItemController: StatusItemController?
    private var pauseExpiryTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Hosted unit tests launch the app executable first. The production panel and
        // global event monitors are irrelevant there and can delay MainActor tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        let coordinator = ActivityCoordinator()
        let motion = MotionPreferences()
        let screenService = ScreenGeometryService()
        let preferences = AppPreferences()
        let loginItem = LoginItemController()
        let music = MusicController(coordinator: coordinator)
        let fileShelf = FileShelfController(coordinator: coordinator)
        let systemStatus = SystemStatusController(coordinator: coordinator)
        let timer = TimerController(coordinator: coordinator)
        let onboardingWindow = OnboardingWindowController(preferences: preferences)
        let settingsWindow = SettingsWindowController(
            preferences: preferences,
            loginItem: loginItem,
            timer: timer,
            screenService: screenService,
            onShowOnboarding: { [weak onboardingWindow] in onboardingWindow?.show() }
        )
        let controller = IslandPanelController(
            coordinator: coordinator,
            motion: motion,
            screenService: screenService,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer,
            preferences: preferences,
            onOpenSettings: { [weak settingsWindow] in settingsWindow?.show() }
        )

        let statusItem = StatusItemController(preferences: preferences)
        statusItem.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        statusItem.onToggleIsland = { [weak self] in
            self?.panelController?.toggleExpanded()
            self?.statusItemController?.refreshMenu()
        }
        statusItem.onPauseOneHour = { [weak preferences] in preferences?.pauseForOneHour() }
        statusItem.onPauseUntilTomorrow = { [weak preferences] in preferences?.pauseUntilTomorrow() }
        statusItem.onResume = { [weak preferences] in preferences?.resume() }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.islandIsExpanded = { [weak controller] in controller?.isExpanded ?? false }

        panelController = controller
        musicController = music
        fileShelfController = fileShelf
        systemStatusController = systemStatus
        timerController = timer
        self.preferences = preferences
        settingsWindowController = settingsWindow
        onboardingWindowController = onboardingWindow
        statusItemController = statusItem

        observePreferences(preferences)
        applyRuntimeConfiguration()
        if !preferences.hasCompletedOnboarding {
            onboardingWindow.show()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        settingsWindowController?.show()
        return true
    }

    func openSettings() {
        settingsWindowController?.show()
    }

    private func observePreferences(_ preferences: AppPreferences) {
        preferences.$menuBarIconVisible
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] visible in
                self?.statusItemController?.setVisible(visible)
            }
            .store(in: &cancellables)

        preferences.$pauseUntil
            .dropFirst()
            .sink { [weak self] _ in self?.applyRuntimeConfiguration() }
            .store(in: &cancellables)

        preferences.$hasCompletedOnboarding
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.applyRuntimeConfiguration() }
            .store(in: &cancellables)

        Publishers.CombineLatest4(
            preferences.$musicEnabled,
            preferences.$fileShelfEnabled,
            preferences.$systemStatusEnabled,
            preferences.$timerEnabled
        )
        .dropFirst()
        .sink { [weak self] _ in self?.applyRuntimeConfiguration() }
        .store(in: &cancellables)
    }

    private func applyRuntimeConfiguration() {
        guard let preferences else { return }
        pauseExpiryTask?.cancel()

        if preferences.musicEnabled && !preferences.isPaused && preferences.hasCompletedOnboarding {
            musicController?.start()
        } else {
            musicController?.stop()
        }
        if preferences.fileShelfEnabled {
            fileShelfController?.start()
        } else {
            fileShelfController?.stop()
        }
        if preferences.systemStatusEnabled && !preferences.isPaused {
            systemStatusController?.start()
        } else {
            systemStatusController?.stop()
        }
        if preferences.timerEnabled {
            timerController?.start()
        } else {
            timerController?.stop()
        }

        if preferences.isPaused, let pauseUntil = preferences.pauseUntil {
            statusItemController?.setVisible(true)
            panelController?.hide()

            let delay = max(0, pauseUntil.timeIntervalSinceNow)
            pauseExpiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.preferences?.clearExpiredPauseIfNeeded()
            }
        } else {
            panelController?.show()
        }
        statusItemController?.refreshMenu()
    }
}
