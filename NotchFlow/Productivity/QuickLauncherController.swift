import AppKit
import Combine
import Foundation

struct QuickLaunchApp: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let url: URL

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

@MainActor
final class QuickLauncherController: ObservableObject {
    @Published private(set) var currentApplication: QuickLaunchApp?
    @Published private(set) var recentApplications: [QuickLaunchApp] = []
    @Published private(set) var commonApplications: [QuickLaunchApp] = []

    private nonisolated(unsafe) var observer: NSObjectProtocol?

    init() {
        refreshCommonApplications()
        capture(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor [weak self] in self?.capture(application) }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func launch(_ application: QuickLaunchApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: application.url,
            configuration: configuration
        )
    }

    func activateCurrentApplication() {
        guard let currentApplication else { return }
        launch(currentApplication)
    }

    private func capture(_ runningApplication: NSRunningApplication?) {
        guard let runningApplication,
              runningApplication.bundleIdentifier != Bundle.main.bundleIdentifier,
              let bundleURL = runningApplication.bundleURL
        else { return }
        let item = QuickLaunchApp(
            id: runningApplication.bundleIdentifier ?? bundleURL.path,
            name: runningApplication.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: runningApplication.bundleIdentifier,
            url: bundleURL
        )
        currentApplication = item
        recentApplications.removeAll { $0.id == item.id }
        recentApplications.insert(item, at: 0)
        recentApplications = Array(recentApplications.prefix(6))
    }

    private func refreshCommonApplications() {
        let bundleIdentifiers = [
            "com.apple.finder",
            "com.apple.Safari",
            "com.apple.MobileSMS",
            "com.apple.Notes",
            "com.apple.Music",
            "com.microsoft.VSCode"
        ]
        commonApplications = bundleIdentifiers.compactMap { identifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            else { return nil }
            let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                ?? url.deletingPathExtension().lastPathComponent
            return QuickLaunchApp(
                id: identifier,
                name: name,
                bundleIdentifier: identifier,
                url: url
            )
        }
    }
}
