import Foundation

protocol TimerStateStoring {
    func load() -> TimerRuntimeState?
    func save(_ state: TimerRuntimeState)
    func clear()
}

struct UserDefaultsTimerStore: TimerStateStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "NotchFlow.timer.state.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> TimerRuntimeState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let decoded = try? JSONDecoder().decode(TimerRuntimeState.self, from: data),
              let normalized = decoded.normalizedForRestore()
        else {
            clear()
            return nil
        }
        if normalized != decoded {
            save(normalized)
        }
        return normalized
    }

    func save(_ state: TimerRuntimeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
