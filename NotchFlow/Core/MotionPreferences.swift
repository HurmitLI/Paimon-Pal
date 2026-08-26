import AppKit
import Combine
import SwiftUI

@MainActor
final class MotionPreferences: NSObject, ObservableObject {
    @Published private(set) var reduceMotion: Bool

    override init() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    var swiftUIAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.18)
            : .spring(response: 0.42, dampingFraction: 0.82)
    }

    var windowAnimationDuration: TimeInterval {
        reduceMotion ? 0.18 : 0.40
    }

    @objc private func displayOptionsChanged() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
