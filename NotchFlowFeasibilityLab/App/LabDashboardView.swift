import SwiftUI

struct LabDashboardView: View {
    @State private var screens: [ScreenGeometrySnapshot] = []
    @StateObject private var panelController = LabPanelController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("NotchFlow 技术可行性实验室")
                    .font(.largeTitle.bold())
                Text("当前仅验证底层能力。这里不是正式产品界面，也不会在本阶段确定最终视觉样式。")
                    .foregroundStyle(.secondary)

                GroupBox("实验 1 · 屏幕与刘海几何") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("重新读取屏幕数据") {
                            screens = ScreenGeometryProbe.snapshots()
                        }
                        .buttonStyle(.borderedProminent)

                        if screens.isEmpty {
                            Text("尚未读取")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(screens) { screen in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(screen.modeDescription)
                                        .font(.headline)
                                        .foregroundStyle(screen.hasPhysicalNotch ? .green : .orange)
                                    ForEach(screen.evidenceLines, id: \.self) { line in
                                        Text(line)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                GroupBox("实验 2 · 顶部 NSPanel") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("浮层应贴合当前主屏顶部中央，并能在收起与展开状态间切换。")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("显示收起态") { panelController.showCollapsed() }
                            Button("显示展开态") { panelController.showExpanded() }
                            Button("隐藏浮层") { panelController.hide() }
                        }
                        .buttonStyle(.bordered)
                        Text("当前状态：\(panelController.isVisible ? panelController.presentation.rawValue : "已隐藏")")
                            .font(.system(.body, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                GroupBox("实验 3 · 音乐状态与控制") {
                    MediaControlLabView()
                }

                GroupBox("实验 4 · 电池、音量与亮度边界") {
                    SystemCapabilityLabView()
                }

                GroupBox("实验 5 · 文件暂存、拖出与 AirDrop") {
                    FileShelfLabView()
                }
            }
            .padding(24)
        }
        .onAppear {
            screens = ScreenGeometryProbe.snapshots()
            panelController.showCollapsed()
        }
    }
}
