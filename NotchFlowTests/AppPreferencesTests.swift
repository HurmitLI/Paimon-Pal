import XCTest
@testable import NotchFlow

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testOnboardingDefaultsToIncompleteAndPersistsCompletion() {
        let suite = "NotchFlowTests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = AppPreferences(defaults: defaults)
        XCTAssertFalse(initial.hasCompletedOnboarding)

        initial.completeOnboarding()
        XCTAssertTrue(initial.hasCompletedOnboarding)
        XCTAssertTrue(AppPreferences(defaults: defaults).hasCompletedOnboarding)

        initial.resetOnboarding()
        XCTAssertFalse(AppPreferences(defaults: defaults).hasCompletedOnboarding)
    }

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "NotchFlowTests.AppPreferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToVisibleMenuBarAndActiveState() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.menuBarIconVisible)
        XCTAssertTrue(preferences.musicEnabled)
        XCTAssertTrue(preferences.fileShelfEnabled)
        XCTAssertTrue(preferences.systemStatusEnabled)
        XCTAssertTrue(preferences.timerEnabled)
        XCTAssertTrue(preferences.petVoiceEnabled)
        XCTAssertEqual(preferences.displayTargetMode, .builtIn)
        XCTAssertNil(preferences.specificDisplayID)
        XCTAssertEqual(preferences.fullScreenBehavior, .hidden)
        XCTAssertEqual(preferences.externalDisplayTopOffset, 6)
        XCTAssertEqual(preferences.floatingCapsuleWidthAdjustment, 0)
        XCTAssertNil(preferences.petDesktopPlacement)
        XCTAssertFalse(preferences.isPaused)
        XCTAssertNil(preferences.pauseUntil)
    }

    func testFeatureTogglesPersistIndependently() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.musicEnabled = false
        preferences.fileShelfEnabled = true
        preferences.systemStatusEnabled = false
        preferences.timerEnabled = true
        preferences.petVoiceEnabled = false

        let restored = AppPreferences(defaults: defaults)
        XCTAssertFalse(restored.musicEnabled)
        XCTAssertTrue(restored.fileShelfEnabled)
        XCTAssertFalse(restored.systemStatusEnabled)
        XCTAssertTrue(restored.timerEnabled)
        XCTAssertFalse(restored.petVoiceEnabled)
    }

    func testOneHourPausePersistsAndForcesVisibleRecoveryEntry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let preferences = AppPreferences(defaults: defaults, now: { now })
        preferences.menuBarIconVisible = false

        preferences.pauseForOneHour()

        XCTAssertEqual(preferences.pauseUntil, now.addingTimeInterval(3_600))
        XCTAssertTrue(preferences.menuBarIconVisible)

        let restored = AppPreferences(defaults: defaults, now: { now.addingTimeInterval(30) })
        XCTAssertTrue(restored.isPaused)
        XCTAssertTrue(restored.menuBarIconVisible)
    }

    func testExpiredPauseIsClearedOnLaunch() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        defaults.set(now.addingTimeInterval(-1), forKey: "settings.general.pauseUntil")

        let preferences = AppPreferences(defaults: defaults, now: { now })

        XCTAssertFalse(preferences.isPaused)
        XCTAssertNil(preferences.pauseUntil)
        XCTAssertNil(defaults.object(forKey: "settings.general.pauseUntil"))
    }

    func testPauseUntilTomorrowUsesNextStartOfDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 27, hour: 15, minute: 30
        ))!
        let expected = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 28, hour: 0, minute: 0
        ))!
        let preferences = AppPreferences(
            defaults: defaults,
            now: { now },
            calendar: calendar
        )

        preferences.pauseUntilTomorrow()

        XCTAssertEqual(preferences.pauseUntil, expected)
    }

    func testResumeClearsPersistedPause() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let preferences = AppPreferences(defaults: defaults, now: { now })
        preferences.pauseForOneHour()

        preferences.resume()

        XCTAssertFalse(preferences.isPaused)
        XCTAssertNil(preferences.pauseUntil)
        XCTAssertNil(defaults.object(forKey: "settings.general.pauseUntil"))
    }

    func testDisplayPreferencesPersist() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.displayTargetMode = .specific
        preferences.specificDisplayID = "display-2"
        preferences.fullScreenBehavior = .importantOnly
        preferences.externalDisplayTopOffset = 18
        preferences.floatingCapsuleWidthAdjustment = 24

        let restored = AppPreferences(defaults: defaults)

        XCTAssertEqual(restored.displayTargetMode, .specific)
        XCTAssertEqual(restored.specificDisplayID, "display-2")
        XCTAssertEqual(restored.fullScreenBehavior, .importantOnly)
        XCTAssertEqual(restored.externalDisplayTopOffset, 18)
        XCTAssertEqual(restored.floatingCapsuleWidthAdjustment, 24)
    }

    func testPetDesktopPlacementPersistsAndCanReturnToNotch() {
        let preferences = AppPreferences(defaults: defaults)
        let placement = PetDesktopPlacement(
            screenID: "built-in-display",
            normalizedX: 0.25,
            normalizedY: 0.7
        )

        preferences.savePetDesktopPlacement(placement)

        XCTAssertEqual(preferences.petDesktopPlacement, placement)
        XCTAssertEqual(AppPreferences(defaults: defaults).petDesktopPlacement, placement)

        preferences.clearPetDesktopPlacement()

        XCTAssertNil(preferences.petDesktopPlacement)
        XCTAssertNil(AppPreferences(defaults: defaults).petDesktopPlacement)
    }

    func testMalformedPetDesktopPlacementIsRemovedOnLaunch() {
        defaults.set(Data("not-json".utf8), forKey: "settings.pet.desktopPlacement")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertNil(preferences.petDesktopPlacement)
        XCTAssertNil(defaults.object(forKey: "settings.pet.desktopPlacement"))
    }

    func testInvalidDisplaySettingsFallBackAndAdjustmentsAreBounded() {
        defaults.set("not-a-mode", forKey: "settings.display.targetMode")
        defaults.set("not-a-policy", forKey: "settings.display.fullScreenBehavior")
        defaults.set(100, forKey: "settings.display.externalTopOffset")
        defaults.set(-100, forKey: "settings.display.floatingCapsuleWidthAdjustment")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.displayTargetMode, .builtIn)
        XCTAssertEqual(preferences.fullScreenBehavior, .hidden)
        XCTAssertEqual(preferences.externalDisplayTopOffset, 40)
        XCTAssertEqual(preferences.floatingCapsuleWidthAdjustment, -40)
        XCTAssertEqual(defaults.string(forKey: "settings.display.targetMode"), "builtIn")
        XCTAssertEqual(defaults.string(forKey: "settings.display.fullScreenBehavior"), "hidden")
        XCTAssertEqual(defaults.double(forKey: "settings.display.externalTopOffset"), 40)
        XCTAssertEqual(defaults.double(forKey: "settings.display.floatingCapsuleWidthAdjustment"), -40)
    }

    func testMalformedTypesAndBlankDisplayIdentifierAreRepairedDurably() {
        defaults.set("not-a-boolean", forKey: "settings.features.musicEnabled")
        defaults.set("   ", forKey: "settings.display.specificDisplayID")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.musicEnabled)
        XCTAssertNil(preferences.specificDisplayID)
        XCTAssertEqual(defaults.object(forKey: "settings.features.musicEnabled") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "settings.display.specificDisplayID"))
    }
}
