import Foundation

enum IslandPresentation: String, CaseIterable, Equatable {
    case silent
    case compact
    case temporaryHUD
    case hoverPreview
    case expanded
    case fileReceiving

    var displayName: String {
        switch self {
        case .silent: "S0 静默收起"
        case .compact: "S1 紧凑活动"
        case .temporaryHUD: "S2 临时 HUD"
        case .hoverPreview: "S3 悬停预览"
        case .expanded: "S4 两翼快捷控制"
        case .fileReceiving: "S5 文件接收"
        }
    }
}

enum IslandActivityKind: String, CaseIterable, Equatable {
    case fileDrop
    case criticalSystem
    case userInteraction
    case ringingTimer
    case timer
    case music
    case systemHUD

    var priority: Int {
        switch self {
        case .fileDrop: 700
        case .criticalSystem: 600
        case .userInteraction: 500
        case .ringingTimer: 400
        case .timer: 350
        case .music: 300
        case .systemHUD: 200
        }
    }
}

struct IslandActivity: Identifiable, Equatable {
    let id: String
    let kind: IslandActivityKind
    let title: String
    let detail: String?

    init(id: String, kind: IslandActivityKind, title: String, detail: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

enum IslandState: Equatable {
    case silent
    case compact(IslandActivity)
    case temporaryHUD(IslandActivity)
    case hoverPreview(IslandActivity?)
    case expanded(IslandActivity?)
    case fileReceiving

    var presentation: IslandPresentation {
        switch self {
        case .silent: .silent
        case .compact: .compact
        case .temporaryHUD: .temporaryHUD
        case .hoverPreview: .hoverPreview
        case .expanded: .expanded
        case .fileReceiving: .fileReceiving
        }
    }

    var activity: IslandActivity? {
        switch self {
        case .compact(let activity), .temporaryHUD(let activity): activity
        case .hoverPreview(let activity), .expanded(let activity): activity
        case .silent, .fileReceiving: nil
        }
    }
}
