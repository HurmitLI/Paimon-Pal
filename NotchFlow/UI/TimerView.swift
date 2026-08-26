import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: TimerController
    @State private var customMinutes = 0
    @State private var customSeconds = 30

    private let presets = [5, 10, 15, 25, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("计时器")
                        .font(.title3.bold())
                    Text(timer.message)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if timer.state.phase != .idle {
                    Text(phaseTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            if timer.state.phase == .idle {
                idleControls
            } else {
                activeTimer
            }

            Divider()

            HStack {
                Label(timer.notificationStatus, systemImage: "bell")
                    .foregroundStyle(.secondary)
                Spacer()
                if timer.notificationStatus.contains("尚未启用") {
                    Button("启用通知") { timer.requestNotificationAuthorization() }
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷时长")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes) 分钟") {
                        timer.begin(seconds: minutes * 60)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }

            Text("自定义")
                .font(.headline)
            HStack(spacing: 12) {
                Stepper("\(customMinutes) 分", value: $customMinutes, in: 0...99)
                Stepper("\(customSeconds) 秒", value: $customSeconds, in: 0...59)
                Spacer()
                Button("开始") {
                    timer.begin(seconds: customMinutes * 60 + customSeconds)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var activeTimer: some View {
        VStack(spacing: 18) {
            Text(timer.state.phase == .ringing
                 ? "计时结束"
                 : TimerTextFormatter.clock(seconds: timer.remainingSeconds))
                .font(.system(size: 52, weight: .semibold, design: .monospaced))
                .foregroundStyle(timer.remainingSeconds <= 60 && timer.state.phase != .paused ? .orange : .primary)
                .contentTransition(.numericText())

            ProgressView(value: timer.state.phase == .ringing ? 0 : timer.progress)
                .tint(timer.remainingSeconds <= 60 ? .orange : .accentColor)

            HStack(spacing: 12) {
                if timer.state.phase == .running {
                    Button("暂停") { timer.pause() }
                        .buttonStyle(.borderedProminent)
                } else if timer.state.phase == .paused {
                    Button("继续") { timer.resume() }
                        .buttonStyle(.borderedProminent)
                } else if timer.state.phase == .ringing {
                    Button("确认") { timer.acknowledge() }
                        .buttonStyle(.borderedProminent)
                }

                if timer.state.phase != .ringing {
                    Button("结束计时") { timer.cancel() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var phaseTitle: String {
        switch timer.state.phase {
        case .idle: "未开始"
        case .running: "进行中"
        case .paused: "已暂停"
        case .ringing: "已结束"
        }
    }
}
