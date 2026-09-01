import AppKit
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: IslandPanelController?
    private var petPanelController: NotchPetPanelController?
    private var localPetModelController: LocalPetModelController?
    private var continuousVoiceController: PetContinuousVoiceController?
    private var musicController: MusicController?
    private var fileShelfController: FileShelfController?
    private var systemStatusController: SystemStatusController?
    private var timerController: TimerController?
    private var productivityStore: ProductivityStore?
    private var productivityWindowController: ProductivityWindowController?
    private var quickLauncherController: QuickLauncherController?
    private var agentCompletionCenter: AgentCompletionCenter?
    private var recordingController: RecordingController?
    private var mirrorCameraController: MirrorCameraController?
    private var credentialVaultController: CredentialVaultController?
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
        let productivityStore = ProductivityStore()
        let quickLauncher = QuickLauncherController()
        let agentCompletionCenter = AgentCompletionCenter()
        let recordingController = RecordingController()
        let mirrorCameraController = MirrorCameraController()
        let credentialVaultController = CredentialVaultController()
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
        let productivityWindow = ProductivityWindowController(
            store: productivityStore,
            launcher: quickLauncher,
            agentCenter: agentCompletionCenter,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer,
            recording: recordingController,
            mirror: mirrorCameraController,
            vault: credentialVaultController,
            onOpenUtility: { [weak controller] section in
                controller?.openUtilityWindow(section)
            }
        )
        controller.onOpenWorkspace = { [weak productivityWindow] in
            productivityWindow?.show()
        }
        let localPetModel = LocalPetModelController(
            petPanel: petController,
            timer: timer,
            music: music,
            productivityStore: productivityStore,
            preferences: preferences,
            onOpenUtilityWindow: { [weak controller] section in
                controller?.openUtilityWindow(section)
            },
            onOpenWorkspace: { [weak productivityWindow] section in
                productivityWindow?.show(section: section)
            },
            onOpenSettings: { [weak settingsWindow] in
                settingsWindow?.show()
            }
        )
        agentCompletionCenter.onEvent = { [weak coordinator, weak petController] event in
            coordinator?.showTemporaryHUD(
                IslandActivity(
                    id: "agent.\(event.source.rawValue)",
                    kind: .userInteraction,
                    title: event.title,
                    detail: event.source.displayName,
                    systemSymbol: "sparkles"
                ),
                duration: .seconds(3)
            )
            petController?.finishModelInteractionSuccessfully()
        }
        agentCompletionCenter.start()
        let continuousVoice = PetContinuousVoiceController()
        continuousVoice.onTranscriptCommitted = { [weak continuousVoice, weak localPetModel] transcript in
            guard let continuousVoice, let localPetModel else { return }
            continuousVoice.markProcessing()
            localPetModel.sendVoicePrompt(
                transcript,
                onPlaybackStarted: { [weak continuousVoice] in
                    continuousVoice?.markSpeaking()
                },
                onFinished: { [weak continuousVoice] in
                    continuousVoice?.resumeAfterReply()
                }
            )
        }
        continuousVoice.onFailure = { [weak self] message in
            self?.showContinuousVoiceError(message)
        }
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
        statusItem.onOpenWorkspace = { [weak productivityWindow] in
            productivityWindow?.show()
        }
        statusItem.onToggleIsland = { [weak self] in
            self?.panelController?.toggleExpanded()
            self?.statusItemController?.refreshMenu()
        }
        statusItem.onToggleContinuousVoice = { [weak self] in
            self?.toggleContinuousVoiceMode()
        }
        statusItem.continuousVoicePhase = { [weak continuousVoice] in
            continuousVoice?.phase ?? .idle
        }
        statusItem.onPauseOneHour = { [weak preferences] in preferences?.pauseForOneHour() }
        statusItem.onPauseUntilTomorrow = { [weak preferences] in preferences?.pauseUntilTomorrow() }
        statusItem.onResume = { [weak preferences] in preferences?.resume() }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.islandIsExpanded = { [weak controller] in controller?.isExpanded ?? false }
#if DEBUG
        let debugDefaults = UserDefaults.standard
        let showWorkspaceOnce = debugDefaults.bool(forKey: "debug.workspace.showOnce")
        let showWorkspace = ProcessInfo.processInfo.environment["NOTCHFLOW_WORKSPACE_AUTOSHOW"] == "1"
            || showWorkspaceOnce
        let showQuickPromptOnce = debugDefaults.bool(forKey: "debug.pet.showQuickPromptOnce")
        let showConversationOnce = debugDefaults.bool(forKey: "debug.pet.showConversationOnce")
        let runVoiceToolOnce = debugDefaults.bool(forKey: "debug.pet.runVoiceToolOnce")
        let runPromptOnce = debugDefaults.string(forKey: "debug.pet.runPromptOnce")
        debugDefaults.removeObject(forKey: "debug.pet.showQuickPromptOnce")
        debugDefaults.removeObject(forKey: "debug.pet.showConversationOnce")
        debugDefaults.removeObject(forKey: "debug.pet.runVoiceToolOnce")
        debugDefaults.removeObject(forKey: "debug.pet.runPromptOnce")
        debugDefaults.removeObject(forKey: "debug.workspace.showOnce")

        statusItem.onTestLocalModelConversation = { [weak localPetModel] in
            localPetModel?.showConversationPrompt()
        }
        if showWorkspace {
            NSApp.setActivationPolicy(.regular)
            // Wait until launch setup has retained every controller and the
            // accessory-to-regular activation-policy transition has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                productivityWindow.show()
            }
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
        if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_QUICK_PROMPT_AUTOSHOW"] == "1"
            || showQuickPromptOnce {
            DispatchQueue.main.async {
                localPetModel.showQuickPrompt()
            }
        } else if ProcessInfo.processInfo.environment["NOTCHFLOW_PET_CONVERSATION_AUTOSHOW"] == "1"
            || showConversationOnce || runVoiceToolOnce || runPromptOnce != nil {
            DispatchQueue.main.async {
                localPetModel.showConversationPrompt()
            }
        }
        if runVoiceToolOnce {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                localPetModel.draft = "帮我计时10秒"
                localPetModel.sendDraft()
            }
        }
        if let runPromptOnce {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                localPetModel.draft = runPromptOnce
                localPetModel.sendDraft()
            }
        }
#endif

        panelController = controller
        petPanelController = petController
        localPetModelController = localPetModel
        continuousVoiceController = continuousVoice
        musicController = music
        fileShelfController = fileShelf
        systemStatusController = systemStatus
        timerController = timer
        self.productivityStore = productivityStore
        productivityWindowController = productivityWindow
        quickLauncherController = quickLauncher
        self.agentCompletionCenter = agentCompletionCenter
        self.recordingController = recordingController
        self.mirrorCameraController = mirrorCameraController
        self.credentialVaultController = credentialVaultController
        self.preferences = preferences
        settingsWindowController = settingsWindow
        onboardingWindowController = onboardingWindow
        statusItemController = statusItem

        continuousVoice.$phase
            .removeDuplicates()
            .sink { [weak petController, weak statusItem] phase in
                statusItem?.refreshMenu()
                switch phase {
                case .listening, .processing, .requestingPermission:
                    petController?.beginModelListening()
                case .speaking:
                    petController?.beginModelSpeaking()
                case .idle, .failed:
                    petController?.endModelInteraction()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .paimonToggleContinuousVoiceRequested)
            .sink { [weak self] _ in
                self?.toggleContinuousVoiceMode()
            }
            .store(in: &cancellables)

        preferences.$petVoiceEnabled
            .removeDuplicates()
            .dropFirst()
            .sink { [weak continuousVoice] enabled in
                if !enabled { continuousVoice?.stop() }
            }
            .store(in: &cancellables)

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

    func applicationWillTerminate(_ notification: Notification) {
        continuousVoiceController?.stop()
        localPetModelController?.stopSpeech()
        agentCompletionCenter?.stop()
        recordingController?.stopRecording()
        mirrorCameraController?.stop()
    }

    func openSettings() {
        settingsWindowController?.show()
    }

    private func toggleContinuousVoiceMode() {
        guard let continuousVoiceController, let preferences else { return }
        if continuousVoiceController.phase.isActive {
            continuousVoiceController.stop()
            localPetModelController?.stopSpeech()
        } else {
            preferences.petVoiceEnabled = true
            continuousVoiceController.start()
        }
    }

    private func showContinuousVoiceError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AI 对话实验模式已停止"
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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
            continuousVoiceController?.stop()
            localPetModelController?.stopSpeech()
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
