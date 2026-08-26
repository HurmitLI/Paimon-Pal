import SwiftUI

struct SystemStatusView: View {
    @ObservedObject var systemStatus: SystemStatusController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("系统状态")
                    .font(.title3.bold())
                Spacer()
                Button("立即刷新") { systemStatus.refreshNow() }
            }

            Text(systemStatus.message)
                .foregroundStyle(.secondary)

            GroupBox("电池与电源") {
                statusRows
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            GroupBox("声音") {
                audioRows
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            GroupBox("屏幕亮度") {
                Label("当前版本不可用，不显示未经公开接口验证的数值。", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        if let battery = systemStatus.snapshot.battery {
            LabeledContent("当前电量", value: battery.percentage.map { "\($0)%" } ?? "系统未提供")
            LabeledContent("供电来源", value: battery.connection.displayName)
            LabeledContent("充电状态", value: battery.isCharging.map { $0 ? "正在充电" : "未充电" } ?? "未知")
        } else {
            ContentUnavailableView("无法读取电池状态", systemImage: "battery.0percent")
        }
    }

    @ViewBuilder
    private var audioRows: some View {
        if let audio = systemStatus.snapshot.audio {
            LabeledContent("输出音量", value: audio.percentage.map { "\($0)%" } ?? "当前设备未提供")
            LabeledContent("静音状态", value: audio.isMuted.map { $0 ? "已静音" : "未静音" } ?? "当前设备未提供")
        } else {
            ContentUnavailableView("无法读取声音状态", systemImage: "speaker.slash")
        }
    }
}
