import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var message = "正在读取开机启动状态…"

    init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            message = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            message = "登录 Mac 后会自动启动 Paimon Pal。"
        case .requiresApproval:
            isEnabled = false
            message = "需要在系统设置的“登录项”中允许 Paimon Pal。"
        case .notRegistered:
            isEnabled = false
            message = "Paimon Pal 不会随登录自动启动。"
        case .notFound:
            isEnabled = false
            message = "当前构建暂时不能注册开机启动。"
        @unknown default:
            isEnabled = false
            message = "暂时无法确认开机启动状态。"
        }
    }
}
