import Foundation

enum CountdownPhase: String, Codable, Equatable {
    case idle
    case running
    case paused
    case ringing
}

enum TimerTransition: Equatable {
    case none
    case finished
    case autoDismissed
}

struct TimerRuntimeState: Codable, Equatable {
    var phase: CountdownPhase
    var totalSeconds: Int
    var endDate: Date?
    var pausedRemainingSeconds: Int?
    var ringingStartedAt: Date?

    static let idle = TimerRuntimeState(
        phase: .idle,
        totalSeconds: 0,
        endDate: nil,
        pausedRemainingSeconds: nil,
        ringingStartedAt: nil
    )

    var isActive: Bool { phase != .idle }

    mutating func begin(seconds: Int, now: Date) -> Bool {
        guard (1...359_999).contains(seconds) else { return false }
        phase = .running
        totalSeconds = seconds
        endDate = now.addingTimeInterval(TimeInterval(seconds))
        pausedRemainingSeconds = nil
        ringingStartedAt = nil
        return true
    }

    mutating func pause(now: Date) -> Bool {
        guard phase == .running else { return false }
        let remaining = remainingSeconds(at: now)
        guard remaining > 0 else { return false }
        phase = .paused
        pausedRemainingSeconds = remaining
        endDate = nil
        return true
    }

    mutating func resume(now: Date) -> Bool {
        guard phase == .paused,
              let remaining = pausedRemainingSeconds,
              remaining > 0
        else { return false }
        phase = .running
        endDate = now.addingTimeInterval(TimeInterval(remaining))
        pausedRemainingSeconds = nil
        return true
    }

    mutating func cancel() {
        self = .idle
    }

    mutating func acknowledge() {
        guard phase == .ringing else { return }
        self = .idle
    }

    func remainingSeconds(at now: Date) -> Int {
        switch phase {
        case .running:
            guard let endDate else { return 0 }
            return max(0, Int(ceil(endDate.timeIntervalSince(now))))
        case .paused:
            return max(0, pausedRemainingSeconds ?? 0)
        case .idle, .ringing:
            return 0
        }
    }

    mutating func refresh(now: Date) -> TimerTransition {
        switch phase {
        case .running:
            guard remainingSeconds(at: now) == 0 else { return .none }
            phase = .ringing
            endDate = nil
            pausedRemainingSeconds = nil
            ringingStartedAt = now
            return .finished
        case .ringing:
            guard let ringingStartedAt,
                  now.timeIntervalSince(ringingStartedAt) >= 30
            else { return .none }
            self = .idle
            return .autoDismissed
        case .idle, .paused:
            return .none
        }
    }

    mutating func reconcileAfterRestore(now: Date) -> TimerTransition {
        switch phase {
        case .running:
            guard let endDate else {
                self = .idle
                return .autoDismissed
            }
            guard endDate <= now else { return .none }
            let overdue = now.timeIntervalSince(endDate)
            guard overdue < 30 else {
                self = .idle
                return .autoDismissed
            }
            phase = .ringing
            self.endDate = nil
            pausedRemainingSeconds = nil
            ringingStartedAt = endDate
            return .finished
        case .ringing:
            guard let ringingStartedAt,
                  now.timeIntervalSince(ringingStartedAt) < 30
            else {
                self = .idle
                return .autoDismissed
            }
            return .none
        case .paused:
            guard let pausedRemainingSeconds, pausedRemainingSeconds > 0 else {
                self = .idle
                return .autoDismissed
            }
            return .none
        case .idle:
            return .none
        }
    }
}

enum TimerTextFormatter {
    static func clock(seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let remainingSeconds = safe % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func duration(seconds: Int) -> String {
        let safe = max(0, seconds)
        let minutes = safe / 60
        let remainingSeconds = safe % 60
        if minutes == 0 { return "\(remainingSeconds) 秒" }
        if remainingSeconds == 0 { return "\(minutes) 分钟" }
        return "\(minutes) 分 \(remainingSeconds) 秒"
    }
}
