import Combine
import Foundation

enum DisplayTargetMode: String, CaseIterable, Identifiable {
    case builtIn
    case primary
    case specific

    var id: Self { self }

    var displayName: String {
        switch self {
        case .builtIn: "内置屏幕"
        case .primary: "主显示器"
        case .specific: "指定显示器"
        }
    }
}

enum FullScreenBehavior: String, CaseIterable, Identifiable {
    case alwaysShow
    case importantOnly
    case hidden

    var id: Self { self }

    var displayName: String {
        switch self {
        case .alwaysShow: "始终显示"
        case .importantOnly: "仅显示重要提醒"
        case .hidden: "完全隐藏"
        }
    }
}

struct PetDesktopPlacement: Codable, Equatable {
    let screenID: String
    let normalizedX: Double
    let normalizedY: Double

    var isValid: Bool {
        !screenID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            normalizedX.isFinite && normalizedY.isFinite &&
            (0...1).contains(normalizedX) && (0...1).contains(normalizedY)
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let menuBarIconVisible = "settings.general.menuBarIconVisible"
        static let pauseUntil = "settings.general.pauseUntil"
        static let musicEnabled = "settings.features.musicEnabled"
        static let fileShelfEnabled = "settings.features.fileShelfEnabled"
        static let systemStatusEnabled = "settings.features.systemStatusEnabled"
        static let timerEnabled = "settings.features.timerEnabled"
        static let petVoiceEnabled = "settings.features.petVoiceEnabled"
        static let displayTargetMode = "settings.display.targetMode"
        static let specificDisplayID = "settings.display.specificDisplayID"
        static let fullScreenBehavior = "settings.display.fullScreenBehavior"
        static let externalDisplayTopOffset = "settings.display.externalTopOffset"
        static let floatingCapsuleWidthAdjustment = "settings.display.floatingCapsuleWidthAdjustment"
        static let petDesktopPlacement = "settings.pet.desktopPlacement"
        static let onboardingCompleted = "settings.onboarding.completed"
    }

    @Published var menuBarIconVisible: Bool {
        didSet { defaults.set(menuBarIconVisible, forKey: Key.menuBarIconVisible) }
    }
    @Published var musicEnabled: Bool {
        didSet { defaults.set(musicEnabled, forKey: Key.musicEnabled) }
    }
    @Published var fileShelfEnabled: Bool {
        didSet { defaults.set(fileShelfEnabled, forKey: Key.fileShelfEnabled) }
    }
    @Published var systemStatusEnabled: Bool {
        didSet { defaults.set(systemStatusEnabled, forKey: Key.systemStatusEnabled) }
    }
    @Published var timerEnabled: Bool {
        didSet { defaults.set(timerEnabled, forKey: Key.timerEnabled) }
    }
    @Published var petVoiceEnabled: Bool {
        didSet { defaults.set(petVoiceEnabled, forKey: Key.petVoiceEnabled) }
    }
    @Published var displayTargetMode: DisplayTargetMode {
        didSet { defaults.set(displayTargetMode.rawValue, forKey: Key.displayTargetMode) }
    }
    @Published var specificDisplayID: String? {
        didSet {
            if let specificDisplayID {
                defaults.set(specificDisplayID, forKey: Key.specificDisplayID)
            } else {
                defaults.removeObject(forKey: Key.specificDisplayID)
            }
        }
    }
    @Published var fullScreenBehavior: FullScreenBehavior {
        didSet { defaults.set(fullScreenBehavior.rawValue, forKey: Key.fullScreenBehavior) }
    }
    @Published var externalDisplayTopOffset: Double {
        didSet {
            let bounded = Self.boundedExternalTopOffset(externalDisplayTopOffset)
            if bounded != externalDisplayTopOffset {
                externalDisplayTopOffset = bounded
                return
            }
            defaults.set(externalDisplayTopOffset, forKey: Key.externalDisplayTopOffset)
        }
    }
    @Published var floatingCapsuleWidthAdjustment: Double {
        didSet {
            let bounded = Self.boundedWidthAdjustment(floatingCapsuleWidthAdjustment)
            if bounded != floatingCapsuleWidthAdjustment {
                floatingCapsuleWidthAdjustment = bounded
                return
            }
            defaults.set(floatingCapsuleWidthAdjustment, forKey: Key.floatingCapsuleWidthAdjustment)
        }
    }
    @Published private(set) var pauseUntil: Date?
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var petDesktopPlacement: PetDesktopPlacement?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        menuBarIconVisible = defaults.object(forKey: Key.menuBarIconVisible) as? Bool ?? true
        musicEnabled = defaults.object(forKey: Key.musicEnabled) as? Bool ?? true
        fileShelfEnabled = defaults.object(forKey: Key.fileShelfEnabled) as? Bool ?? true
        systemStatusEnabled = defaults.object(forKey: Key.systemStatusEnabled) as? Bool ?? true
        timerEnabled = defaults.object(forKey: Key.timerEnabled) as? Bool ?? true
        petVoiceEnabled = defaults.object(forKey: Key.petVoiceEnabled) as? Bool ?? true
        displayTargetMode = defaults.string(forKey: Key.displayTargetMode)
            .flatMap(DisplayTargetMode.init(rawValue:)) ?? .builtIn
        specificDisplayID = defaults.string(forKey: Key.specificDisplayID)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        fullScreenBehavior = defaults.string(forKey: Key.fullScreenBehavior)
            .flatMap(FullScreenBehavior.init(rawValue:)) ?? .hidden
        externalDisplayTopOffset = Self.boundedExternalTopOffset(
            defaults.object(forKey: Key.externalDisplayTopOffset) as? Double ?? 6
        )
        floatingCapsuleWidthAdjustment = Self.boundedWidthAdjustment(
            defaults.object(forKey: Key.floatingCapsuleWidthAdjustment) as? Double ?? 0
        )
        hasCompletedOnboarding = defaults.object(forKey: Key.onboardingCompleted) as? Bool ?? false
        petDesktopPlacement = (defaults.data(forKey: Key.petDesktopPlacement))
            .flatMap { try? JSONDecoder().decode(PetDesktopPlacement.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }

        if let storedDate = defaults.object(forKey: Key.pauseUntil) as? Date,
           storedDate > now() {
            pauseUntil = storedDate
            // A paused accessory app must retain a visible way to resume.
            menuBarIconVisible = true
            defaults.set(true, forKey: Key.menuBarIconVisible)
        } else {
            pauseUntil = nil
            defaults.removeObject(forKey: Key.pauseUntil)
        }

        repairPersistedValues()
    }

    var isPaused: Bool {
        guard let pauseUntil else { return false }
        return pauseUntil > now()
    }

    func pauseForOneHour() {
        pause(until: now().addingTimeInterval(60 * 60))
    }

    func pauseUntilTomorrow() {
        let current = now()
        let startOfToday = calendar.startOfDay(for: current)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? current.addingTimeInterval(24 * 60 * 60)
        pause(until: tomorrow)
    }

    func resume() {
        pauseUntil = nil
        defaults.removeObject(forKey: Key.pauseUntil)
    }

    func clearExpiredPauseIfNeeded() {
        guard let pauseUntil, pauseUntil <= now() else { return }
        resume()
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.onboardingCompleted)
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        defaults.removeObject(forKey: Key.onboardingCompleted)
    }

    func savePetDesktopPlacement(_ placement: PetDesktopPlacement) {
        guard placement.isValid,
              let data = try? JSONEncoder().encode(placement) else { return }
        petDesktopPlacement = placement
        defaults.set(data, forKey: Key.petDesktopPlacement)
    }

    func clearPetDesktopPlacement() {
        petDesktopPlacement = nil
        defaults.removeObject(forKey: Key.petDesktopPlacement)
    }

    private func pause(until date: Date) {
        menuBarIconVisible = true
        pauseUntil = date
        defaults.set(date, forKey: Key.pauseUntil)
    }

    /// Rewrites every setting with its validated runtime value. This makes a
    /// one-time fallback durable instead of repeatedly reading malformed data
    /// on every launch.
    private func repairPersistedValues() {
        defaults.set(menuBarIconVisible, forKey: Key.menuBarIconVisible)
        defaults.set(musicEnabled, forKey: Key.musicEnabled)
        defaults.set(fileShelfEnabled, forKey: Key.fileShelfEnabled)
        defaults.set(systemStatusEnabled, forKey: Key.systemStatusEnabled)
        defaults.set(timerEnabled, forKey: Key.timerEnabled)
        defaults.set(petVoiceEnabled, forKey: Key.petVoiceEnabled)
        defaults.set(displayTargetMode.rawValue, forKey: Key.displayTargetMode)
        defaults.set(fullScreenBehavior.rawValue, forKey: Key.fullScreenBehavior)
        defaults.set(externalDisplayTopOffset, forKey: Key.externalDisplayTopOffset)
        defaults.set(
            floatingCapsuleWidthAdjustment,
            forKey: Key.floatingCapsuleWidthAdjustment
        )
        if hasCompletedOnboarding {
            defaults.set(true, forKey: Key.onboardingCompleted)
        } else {
            defaults.removeObject(forKey: Key.onboardingCompleted)
        }
        if let specificDisplayID {
            defaults.set(specificDisplayID, forKey: Key.specificDisplayID)
        } else {
            defaults.removeObject(forKey: Key.specificDisplayID)
        }
        if let petDesktopPlacement,
           let data = try? JSONEncoder().encode(petDesktopPlacement) {
            defaults.set(data, forKey: Key.petDesktopPlacement)
        } else {
            defaults.removeObject(forKey: Key.petDesktopPlacement)
        }
    }

    private static func boundedExternalTopOffset(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 6, 0), 40)
    }

    private static func boundedWidthAdjustment(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, -40), 80)
    }
}
