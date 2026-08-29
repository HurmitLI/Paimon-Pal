import AppKit
import SwiftUI

final class PetAnimationLabAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PetAnimationLabApp: App {
    @NSApplicationDelegateAdaptor(PetAnimationLabAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("NotchFlow 宠物动画播放器") {
            PetAnimationLabView()
        }
        .defaultSize(width: 980, height: 720)
        .windowResizability(.contentMinSize)
    }
}
