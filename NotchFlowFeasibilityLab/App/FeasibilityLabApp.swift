import SwiftUI

@main
struct NotchFlowFeasibilityLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("NotchFlow 可行性实验室") {
            LabDashboardView()
                .frame(minWidth: 720, minHeight: 560)
        }
        .defaultSize(width: 820, height: 680)
        .windowResizability(.contentMinSize)
    }
}

