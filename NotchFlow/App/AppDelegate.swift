import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: IslandPanelController?

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
        let music = MusicController(coordinator: coordinator)
        let fileShelf = FileShelfController(coordinator: coordinator)
        let systemStatus = SystemStatusController(coordinator: coordinator)
        let timer = TimerController(coordinator: coordinator)
        let controller = IslandPanelController(
            coordinator: coordinator,
            motion: motion,
            screenService: screenService,
            music: music,
            fileShelf: fileShelf,
            systemStatus: systemStatus,
            timer: timer
        )
        panelController = controller
        controller.show()
        music.start()
        fileShelf.start()
        systemStatus.start()
        timer.start()
    }
}
