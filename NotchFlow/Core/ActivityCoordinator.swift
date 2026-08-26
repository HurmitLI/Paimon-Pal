import Combine
import Foundation

@MainActor
final class ActivityCoordinator: ObservableObject {
    private struct QueuedHUD {
        let activity: IslandActivity
        let duration: Duration
    }

    @Published private(set) var state: IslandState = .silent

    private var activities: [String: IslandActivity] = [:]
    private var queuedHUD: QueuedHUD?
    private var hoverTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var stateBeforeFileReceiving: IslandState?

    var orderedActivities: [IslandActivity] {
        activities.values.sorted {
            if $0.kind.priority == $1.kind.priority { return $0.id < $1.id }
            return $0.kind.priority > $1.kind.priority
        }
    }

    func upsert(_ activity: IslandActivity) {
        guard activities[activity.id] != activity else { return }
        activities[activity.id] = activity
        reconcileAfterActivitiesChanged()
    }

    func removeActivity(id: String) {
        guard activities.removeValue(forKey: id) != nil else { return }
        reconcileAfterActivitiesChanged()
    }

    func pointerEntered() {
        leaveTask?.cancel()
        hoverTask?.cancel()
        guard state.presentation == .silent || state.presentation == .compact else { return }
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else { return }
            state = .hoverPreview(highestActivity)
        }
    }

    func pointerExited(
        isPointerOutside: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        hoverTask?.cancel()
        guard state.presentation == .hoverPreview else { return }
        leaveTask?.cancel()
        leaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, isPointerOutside(), let self else { return }
            restoreBaseState()
        }
    }

    func toggleExpanded() {
        cancelPointerTasks()
        switch state.presentation {
        case .expanded:
            collapse()
        default:
            showExpanded()
        }
    }

    func showExpanded() {
        cancelPointerTasks()
        state = .expanded(state.activity ?? highestActivity)
    }

    func collapse() {
        cancelPointerTasks()
        if let queuedHUD {
            self.queuedHUD = nil
            presentHUD(queuedHUD.activity, duration: queuedHUD.duration)
        } else {
            restoreBaseState()
        }
    }

    func showTemporaryHUD(_ activity: IslandActivity, duration: Duration = .milliseconds(1500)) {
        if state.presentation == .fileReceiving ||
            (isUserOperating && activity.kind != .criticalSystem) {
            queuedHUD = QueuedHUD(activity: activity, duration: duration)
            return
        }
        presentHUD(activity, duration: duration)
    }

    func beginFileReceiving() {
        guard state.presentation != .fileReceiving else { return }
        cancelPointerTasks()
        stateBeforeFileReceiving = state
        state = .fileReceiving
    }

    func endFileReceiving() {
        guard state.presentation == .fileReceiving else { return }
        state = stateBeforeFileReceiving ?? baseState
        stateBeforeFileReceiving = nil
    }

    func clearAllActivities() {
        activities.removeAll()
        queuedHUD = nil
        dismissTask?.cancel()
        state = .silent
    }

    private var highestActivity: IslandActivity? {
        orderedActivities.first
    }

    private var baseState: IslandState {
        highestActivity.map(IslandState.compact) ?? .silent
    }

    private var isUserOperating: Bool {
        state.presentation == .expanded
    }

    private func restoreBaseState() {
        dismissTask?.cancel()
        state = baseState
    }

    private func reconcileAfterActivitiesChanged() {
        switch state.presentation {
        case .silent, .compact:
            restoreBaseState()
        case .hoverPreview:
            state = .hoverPreview(highestActivity)
        case .temporaryHUD, .expanded, .fileReceiving:
            break
        }
    }

    private func presentHUD(_ activity: IslandActivity, duration: Duration = .milliseconds(1500)) {
        dismissTask?.cancel()
        state = .temporaryHUD(activity)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            restoreBaseState()
        }
    }

    private func cancelPointerTasks() {
        hoverTask?.cancel()
        leaveTask?.cancel()
    }
}
