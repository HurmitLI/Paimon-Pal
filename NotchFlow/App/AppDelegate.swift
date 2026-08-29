import AppKit
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: IslandPanelController?
    private var petPanelController: NotchPetPanelController?
    private var localPetModelController: LocalPetModelController?
    private var musicController: MusicController?
    private var fileShelfController: FileShelfController?
    private var systemStatusController: SystemStatusController?
    private var timerController: TimerController?
    private var preferences: AppPreferences?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var statusItemController: StatusItemController?
    private var pauseExpiryTask: Task<Void, Never>?
    private var singleInstanceLock: SingleInstanceLock?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Hosted unit tests launch the app executable first. The production panel and
        // global event monitors are irrelevant there and can delay MainActor tests.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        guard let instanceLock = SingleInstanceLock.acquireDefault() else {
            NSApp.terminate(nil)
            return
        }
        singleInstanceLock = instanceLock

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
        let petController = NotchPetPanelController(
            coordinator: coordinator,
            screenService: screenService,
            preferences: preferences
        )
        let localPetModel = LocalPetModelController(
            petPanel: petController,
            timer: timer,
            preferences: preferences,
            onOpenUtilityWindow: { [weak controller] section in
                controller?.openUtilityWindow(section)
            },
            onOpenSettings: { [weak settingsWindow] in
                settingsWindow?.show()
            }
        )
        petController.onPetClicked = { [weak localPetModel] in
            localPetModel?.showQuickPrompt()
        }
        petController.onPresentationFrameChanged = { [weak localPetModel] in
            localPetModel?.repositionQuickPrompt()
        }
        petController.onPetDocked = { [weak localPetModel] in
            localPetModel?.closeQuickPrompt()
        }

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
#if DEBUG
        statusItem.onTestLocalModelConversation = { [weak localPetModel] in
            localPetModel?.showConversationPrompt()
        }
        statusItem.onTogglePetListening = { [weak petController, weak statusItem] in
            petController?.toggleListeningForTesting()
            statusItem?.refreshMenu()
        }
        statusItem.petIsListening = { [weak petController] in
            petController?.isListening ?? false
        }
        statusItem.onTogglePetSpeaking = { [weak petController, weak statusItem] in
            petController?.toggleSpeakingForTesting()
            statusItem?.refreshMenu()
        }
        statusItem.petIsSpeaking = { [weak petController] in
            petController?.isSpeaking ?? false
        }
        statusItem.onTestPetSuccess = { [weak petController] in
            petController?.celebrateSuccessForTesting()
        }
        if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_QUICK_PROMPT_AUTOSHOW"] == "1" {
            DispatchQueue.main.async {
                localPetModel.showQuickPrompt()
            }
        } else if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_CONVERSATION_AUTOSHOW"] == "1" {
            DispatchQueue.main.async {
                localPetModel.showConversationPrompt()
            }
        }
#endif

        panelController = controller
        petPanelController = petController
        localPetModelController = localPetModel
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
            petPanelController?.hide()

            let delay = max(0, pauseUntil.timeIntervalSinceNow)
            pauseExpiryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.preferences?.clearExpiredPauseIfNeeded()
            }
        } else {
            panelController?.show()
            if preferences.hasCompletedOnboarding {
                petPanelController?.show()
            } else {
                petPanelController?.hide()
            }
        }
        statusItemController?.refreshMenu()
    }
}

final class SingleInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    static func acquireDefault() -> SingleInstanceLock? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent(
            "Paimon Pal",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        return acquire(at: directory.appendingPathComponent("running.lock"))
    }

    static func acquire(at url: URL) -> SingleInstanceLock? {
        let fileDescriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard fileDescriptor >= 0 else { return nil }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fileDescriptor)
            return nil
        }
        return SingleInstanceLock(fileDescriptor: fileDescriptor)
    }

    deinit {
        _ = flock(fileDescriptor, LOCK_UN)
        _ = Darwin.close(fileDescriptor)
    }
}
