# 第一阶段技术开发文档｜NotchFlow 技术可行性验证

> 文档版本：v1.0  
> 更新日期：2026-08-26  
> 对应 PRD 阶段：阶段 0｜技术验证  
> 配套文档：《NotchFlow PRD v1.0》《NotchFlow 技术适配声明 v1.0》《AI Agent 产品 Vibe Coding 通用技术栈手册 V2.1》  
> 执行约束：本文档描述未来开发要求；当前用户要求“不开发”，因此尚未创建工程、安装依赖或运行验证

---

## 一、阶段目标

### 1.1 阶段目的

第一阶段不交付完整产品，而是回答一个问题：

> NotchFlow 的五类关键系统能力，能否在 macOS 14+、真实 MacBook 和未来签名分发条件下稳定实现？

需要得到可追溯的“可实现 / 可实现但有限制 / 不可稳定实现 / 当前阻塞”结论。不能因为某个开源项目做过类似效果，就把能力视为已经验证。

### 1.2 交付范围

本阶段验证五个实验域：

| 实验域 | 核心问题 | 对应 PRD |
|---|---|---|
| LAB-01 屏幕几何 | 能否准确识别物理刘海，并在无刘海屏降级为悬浮胶囊 | 6.1、6.2、8.1 |
| LAB-02 面板与 Space | `NSPanel` 能否稳定显示、交互、不抢焦点，并遵循全屏/多屏策略 | 5、8 |
| LAB-03 音乐能力 | Apple Music/Spotify 能可靠提供哪些信息和控制，权限如何表现 | 7.1、9 |
| LAB-04 系统状态 | 电源、电量、音量和亮度分别能否稳定监听 | 7.3、9 |
| LAB-05 文件与 AirDrop | 文件能否安全拖入、复制、拖出并唤起系统 AirDrop | 7.2、9 |

### 1.3 阶段产物

未来执行本阶段时，应产生：

1. 一个仅供验证的原生 macOS 实验工程 `NotchFlowFeasibilityLab`。
2. 五个相互隔离的实验模块。
3. 一个简单实验控制窗口和一个顶部实验面板。
4. XCTest 自动化测试。
5. `capability-report.json` 版本化能力报告。
6. 实机验证记录、必要截图和系统日志摘要。
7. 一份阶段结论，明确每项 P0 是保留、降级还是需要移出首版。

### 1.4 阶段退出条件

满足以下条件才允许进入 PRD 阶段 1“交互底座”：

- 五个实验域都有明确结论，不存在未说明的“应该能做”。
- 物理刘海几何和 `NSPanel` 稳定性通过真实设备验证。
- Apple Music 通过真实应用验证；Spotify 已验证或明确标记为外部环境阻塞。
- 电源、电量和音量监听有稳定路径。
- 亮度监听得到“可用方案”或按 PRD 启用明确降级。
- 文件拖入、容器复制、拖出和 AirDrop 系统面板均完成验证。
- 自动化测试和人工冒烟结果没有互相矛盾。
- 所有需要权限的能力均验证允许、拒绝和撤销后的行为。

### 1.5 明确不做

本阶段不得提前实现：

- 正式产品 UI、正式灵动岛视觉和品牌设计。
- 完整 S0–S6 状态机、活动优先级队列和四模块业务编排。
- 正式动画、果冻形变、专辑封面取色和音频可视化。
- 完整文件架、24 小时清理和用户文件索引恢复。
- 正式计时器。
- 设置页、首次启动引导、菜单栏完整功能和开机启动。
- App Store 上架、正式签名、公证和 DMG。
- Web 前端、后端 API、数据库、云部署、AI 模型或遥测。

### 1.6 本阶段打通的主链路片段

```text
真实系统/用户动作
→ 系统框架或权限边界
→ 单一能力 Adapter
→ 标准化 CapabilityResult
→ 最小实验界面可见
→ XCTest/人工验证
→ 版本化能力报告
→ 得出保留/降级/阻塞结论
```

---

## 二、技术适配摘要

### 2.1 适配结论

- 产品是纯端侧 macOS 工具，不适用通用手册的 Python/FastAPI/Next.js 默认栈。
- 采用 Swift + SwiftUI + AppKit。
- 采用终端能力先行的纵向技术验证，不采用后端先行。
- 第一阶段不引入第三方 Swift Package。
- 无模型、无 API Key、无数据库、无网络端口和外部部署服务。

### 2.2 本阶段采用

- AppKit：`NSPanel`、屏幕和原生拖放/分享能力。
- SwiftUI：实验控制界面与结果展示。
- XCTest：纯逻辑、系统适配层和最小 UI 自动化验证。
- OSLog：结构化诊断日志。
- 版本化 JSON：保存能力验证结论，不保存正式用户数据。

### 2.3 本阶段启用的按需模块

- Core Audio：由音量 P0 需求触发。
- IOKit Power Sources：由电量/充电 P0 需求触发。
- Apple Events：由 Apple Music/Spotify 控制 P0 需求触发。
- Uniform Type Identifiers 和 App Sandbox：由文件暂存 P0 需求触发。
- `NSSharingService`：由 AirDrop P0 需求触发。

### 2.4 本阶段偏离/暂缓

- 不建立 HTTP API；用 Swift Protocol 作为独立可测试入口。
- 不建立正式产品数据模型；只保存实验结果。
- 不制作正式前端；实验控制窗口属于一次性验证工具。
- 不执行真实模型冒烟；用真实 Mac 和系统应用冒烟替代。

---

## 三、技术栈与系统框架

### 3.1 技术栈

| 层 | 技术 | 用途 |
|---|---|---|
| 语言 | Swift | 原生业务与系统能力验证 |
| UI | SwiftUI | 实验控制窗口和结果卡片 |
| 窗口 | AppKit / `NSPanel` | 顶部浮层、焦点、Space、全屏和多屏 |
| 屏幕 | AppKit / `NSScreen` | 安全区、刘海和显示器几何 |
| 音量 | Core Audio | 默认输出设备、音量、静音监听 |
| 电源 | IOKit Power Sources | 电池、电源和充电状态 |
| 音乐 | Apple Events / ScriptingBridge | Apple Music、Spotify 信息与控制边界 |
| 文件 | AppKit drag and drop、Foundation、UTType | 类型校验、复制、拖出 |
| 分享 | `NSSharingService` | AirDrop 系统流程 |
| 日志 | OSLog | 诊断与证据 |
| 测试 | XCTest | 自动化回归与 UI 测试 |

### 3.2 最低系统与编译要求

- Deployment Target：macOS 14.0。
- 开发设备：Apple Silicon MacBook Pro。
- 必须安装完整稳定版 Xcode；当前只有 Command Line Tools，不能开工。
- 完整 Xcode 安装后，再将实际 Xcode、Swift 和 SDK 版本写入 README 与验证报告。
- 第一阶段不得为兼容旧系统引入 `#if` 大量分叉；针对 macOS 14+ 使用可用性检查。

### 3.3 第三方依赖

本阶段为零。

以下内容不得引入：

- MediaRemote 私有框架封装。
- 动画库。
- 启动项库。
- 数据库或 ORM。
- 网络请求库。
- 遥测和崩溃上报 SDK。

如果苹果系统框架无法满足 P0，应先在能力报告中记录缺口，不得用未经审查的第三方包直接掩盖结论。

### 3.4 模型

无。

- 不需要模型厂商、模型名、API Key 或费用预算。
- 不创建 Prompt、RAG、Embedding 或 Agent 工具。
- 不执行真实模型冒烟。

---

## 四、环境与配置

### 4.1 已检查环境

| 项目 | 当前值 |
|---|---|
| macOS | 26.6.2（25G83） |
| Mac | MacBook Pro Mac17,2，Apple M5，24GB |
| 内置屏幕 | 3024 × 1964 Retina |
| 架构 | arm64 |
| Swift CLI | Apple Swift 6.3.3 |
| Git | 2.50.1 |
| Apple Music | 已安装 |
| Spotify | 未安装 |
| 完整 Xcode | 未安装或未被发现 |
| 项目源码 | 无 |
| Git 仓库 | 未初始化 |

### 4.2 开工前准备

1. 安装完整 Xcode。
2. 运行 `xcodebuild -version`，记录版本。
3. 打开 Xcode 完成首次组件安装。
4. 确认本机可运行一个空白 macOS App target。
5. 若首版仍以 Spotify 为 P0，安装 Spotify 桌面客户端。
6. 准备无刘海外接显示器。
7. 初始化 Git，先提交三份文档作为基线。

### 4.3 配置项

本阶段不使用 `.env`。实验配置使用代码中的非秘密默认值或启动参数：

| 配置 | 默认值 | 说明 |
|---|---:|---|
| `targetDisplayMode` | `builtIn` | 默认验证内置屏 |
| `hoverDelayMs` | `180` | 只用于面板交互实验 |
| `panelTopOffset` | `0` | 物理刘海模式 |
| `floatingTopOffset` | `6` | 无刘海屏胶囊 |
| `maxLogEntries` | `500` | 防止实验日志无限增长 |
| `copyTestLimitBytes` | `2147483648` | 对齐 PRD 2GB 提醒边界，只验证判断逻辑，不要求创建 2GB 测试文件 |

### 4.4 Bundle ID 与权限

- 实验工程使用稳定临时 Bundle ID：`com.notchflow.FeasibilityLab`。
- Bundle ID 在阶段内不得频繁修改，否则会影响 TCC 权限复测。
- App Sandbox 默认开启。
- 仅添加实验实际需要的最小 entitlements。
- Apple Events 权限必须指向明确目标应用，不允许任意脚本控制。
- 第一阶段本地验证不要求付费 Apple Developer Program。

### 4.5 端口和外部服务

无。

- 不启动本地 HTTP 服务。
- 不使用数据库服务。
- 不连接云端 API。
- 不要求 Docker、Node.js 或 Python 环境。

---

## 五、项目结构

以下是未来执行第一阶段时允许创建的最小结构：

```text
NotchFlowFeasibilityLab/
├── NotchFlowFeasibilityLab.xcodeproj
├── App/
│   ├── FeasibilityLabApp.swift
│   ├── AppDelegate.swift
│   └── LabDashboardView.swift
├── Core/
│   ├── CapabilityID.swift
│   ├── CapabilityStatus.swift
│   ├── CapabilityResult.swift
│   ├── CapabilityReportStore.swift
│   ├── LabError.swift
│   └── LabLogger.swift
├── Labs/
│   ├── ScreenGeometry/
│   │   ├── ScreenGeometryProbe.swift
│   │   ├── ScreenGeometrySnapshot.swift
│   │   └── ScreenGeometryLabView.swift
│   ├── PanelBehavior/
│   │   ├── LabPanel.swift
│   │   ├── LabPanelController.swift
│   │   └── PanelBehaviorLabView.swift
│   ├── MediaControl/
│   │   ├── MediaPlayerAdapter.swift
│   │   ├── AppleMusicAdapter.swift
│   │   ├── SpotifyAdapter.swift
│   │   └── MediaControlLabView.swift
│   ├── SystemStatus/
│   │   ├── PowerStatusProbe.swift
│   │   ├── AudioVolumeProbe.swift
│   │   ├── BrightnessProbe.swift
│   │   └── SystemStatusLabView.swift
│   └── FileTransfer/
│       ├── FileDropValidator.swift
│       ├── SandboxCopyProbe.swift
│       ├── FileDragSource.swift
│       ├── AirDropProbe.swift
│       └── FileTransferLabView.swift
├── Resources/
│   ├── Info.plist
│   └── NotchFlowFeasibilityLab.entitlements
├── Tests/
│   ├── ScreenGeometryTests.swift
│   ├── CapabilityReportTests.swift
│   ├── FileDropValidatorTests.swift
│   ├── MediaAdapterContractTests.swift
│   └── SystemValueNormalizationTests.swift
└── UITests/
    └── FeasibilityLabUITests.swift

docs/
└── evidence/
    └── phase-0/
        ├── capability-report.json
        ├── manual-test-record.md
        └── screenshots/
```

规则：

- `Labs` 之间不得直接依赖。
- 系统框架调用集中在 Probe/Adapter 中，不写进 SwiftUI View。
- 实验 UI 不承担业务规则，只发起探测和展示结果。
- 不提前创建正式产品的 `Features/NowPlaying`、`FileShelf` 等目录。
- 证据目录不得保存用户真实文件或敏感截图。

---

## 六、数据、资产与状态

### 6.1 持久化方式

本阶段只持久化能力报告，不建立数据库。

- 格式：JSON。
- schema 版本：`1`。
- 写入方式：临时文件写入成功后原子替换。
- 并发边界：只允许主进程中的 ReportStore 串行写入。
- 损坏处理：保留损坏文件副本，重新生成空报告并记录错误。
- 未来迁移：能力报告只用于研发证据，不进入正式产品数据迁移。

### 6.2 能力状态

```swift
enum CapabilityStatus: String, Codable {
    case notStarted
    case running
    case passed
    case passedWithLimitations
    case failed
    case blocked
}
```

状态规则：

- `notStarted → running`：用户或自动化开始实验。
- `running → passed`：全部预定用例通过。
- `running → passedWithLimitations`：主链路成立，但存在明确产品降级。
- `running → failed`：环境具备但能力不可实现或结果不可靠。
- `notStarted/running → blocked`：缺少 Xcode、应用、显示器、权限或测试设备。
- 任何终态重新测试时先进入 `running`，保留历史运行记录。

### 6.3 能力报告结构

```json
{
  "schemaVersion": 1,
  "generatedAt": "ISO-8601",
  "environment": {
    "macOSVersion": "string",
    "hardwareModel": "string",
    "architecture": "arm64",
    "xcodeVersion": "string",
    "appSandboxEnabled": true
  },
  "capabilities": [
    {
      "id": "screen.geometry.physical-notch",
      "status": "passed",
      "summary": "string",
      "limitations": [],
      "evidenceRefs": [],
      "lastTestedAt": "ISO-8601"
    }
  ]
}
```

禁止写入：

- 用户名、Apple ID、Spotify 账号。
- 完整文件名、文件内容和用户目录路径。
- Apple Events 返回的私人播放历史。
- 系统权限数据库内容。

### 6.4 文件实验资产

只使用人工创建的非敏感测试资产：

- 小文本文件。
- 普通图片。
- 测试文件夹。
- 同名测试文件。
- 只用于空间边界判断的模拟元数据。

复制目标使用实验 App Container 的 Application Support 子目录。测试结束后由用户可见的“清理实验文件”按钮删除，仅删除实验自己创建的目录。

### 6.5 本阶段状态机

本阶段不实现 PRD 的完整 S0–S6 产品状态机，只实现实验运行状态：

```text
idle → running → passed / passedWithLimitations / failed / blocked
                  ↓
               rerun → running
```

面板实验允许一个最小 UI 状态：

```text
hidden → collapsed → expanded → hidden
```

该状态只验证窗口和输入行为，不代表正式产品状态机设计完成。

---

## 七、接口与工具设计

### 7.1 外部 API

无。

本阶段不创建 HTTP 接口、SSE、WebSocket 或本地服务端口。

### 7.2 内部探测接口

```swift
protocol CapabilityProbe {
    var id: CapabilityID { get }
    func run() async -> CapabilityResult
}
```

约束：

- `run()` 必须有明确完成或失败结果，不能永久等待。
- 每个系统调用设置合理超时或取消路径。
- 权限拒绝映射为受控 `LabError.permissionDenied`。
- 目标应用未安装映射为 `LabError.targetUnavailable`。
- 系统 API 不可用映射为 `LabError.unsupported`。
- 未知错误只写入内部错误类型，不把调用栈显示给产品经理。

### 7.3 统一错误结构

```swift
struct LabFailure: Codable, Equatable {
    let code: String
    let userMessage: String
    let recoverySuggestion: String?
}
```

建议错误码：

| 错误码 | 含义 |
|---|---|
| `ENV_XCODE_MISSING` | 完整 Xcode 未安装 |
| `ENV_TARGET_APP_MISSING` | Apple Music/Spotify 目标应用缺失 |
| `PERMISSION_DENIED` | 用户拒绝权限 |
| `SCREEN_NOTCH_UNAVAILABLE` | 当前屏幕没有可识别物理刘海 |
| `PANEL_BEHAVIOR_MISMATCH` | 面板行为与预期不符 |
| `MEDIA_COMMAND_UNSUPPORTED` | 播放器不支持某项控制 |
| `SYSTEM_VALUE_UNAVAILABLE` | 系统值无法稳定读取 |
| `FILE_VALIDATION_FAILED` | 拖入文件未通过校验 |
| `FILE_COPY_FAILED` | 文件复制失败 |
| `AIRDROP_UNAVAILABLE` | 系统 AirDrop 服务不可用 |

### 7.4 各实验设计

#### LAB-01：屏幕几何

输入：当前 `NSScreen.screens`。

采集：

- frame、visibleFrame、safeAreaInsets。
- auxiliaryTopLeftArea、auxiliaryTopRightArea。
- backingScaleFactor。
- 是否内置屏、是否主屏。

计算：

```text
notchWidth = screenFrame.width - leftArea.width - rightArea.width
notchHeight = leftArea.height
```

校验：

- 结果为有限正数。
- 刘海矩形不越出屏幕。
- 左右辅助区域总宽不大于屏幕宽度。
- 无辅助区域时进入悬浮胶囊模式，不产生负数或零宽面板。

输出：每块屏幕的 `ScreenGeometrySnapshot` 和验证状态。

#### LAB-02：面板与 Space

验证一个无边框透明 `NSPanel`：

- 顶部中央定位。
- 收起态不抢键盘焦点。
- 展开态允许鼠标交互。
- 透明非交互区域不拦截点击。
- 普通 Space、多 Space、全屏和 Stage Manager 行为可记录。
- 显示器插拔后能重新定位。
- 设置/实验控制窗口保持普通窗口层级，可跨显示器移动。

窗口 CollectionBehavior 需要通过实验确定最终组合，不能只凭示例代码认定。每次组合必须记录系统版本和结果。

#### LAB-03：音乐能力

定义统一能力矩阵：

| 能力 | Apple Music | Spotify |
|---|---|---|
| 检测是否运行 | 待验 | 当前因未安装阻塞 |
| 播放状态 | 待验 | 阻塞 |
| 歌曲名 | 待验 | 阻塞 |
| 艺人 | 待验 | 阻塞 |
| 封面 | 待验 | 阻塞 |
| 当前进度 | 待验 | 阻塞 |
| 总时长 | 待验 | 阻塞 |
| 播放/暂停 | 待验 | 阻塞 |
| 上一首/下一首 | 待验 | 阻塞 |
| 跳转进度 | 待验 | 阻塞 |
| 跳转到播放器 | 待验 | 阻塞 |

规则：

- 只使用明确目标应用的 Apple Events 或公开能力。
- 首次调用前显示用途说明，再触发系统权限提示。
- 分别验证允许、拒绝、系统设置中撤销权限。
- 不使用用户账号凭据。
- 某字段不可用时返回 `nil`，不得伪造默认值。
- 通用系统媒体私有接口不进入第一阶段推荐实现。

#### LAB-04：系统状态

电源/电池验证：

- 是否连接电源。
- 是否正在充电。
- 电量百分比。
- 电池信息不可用时的错误分支。

音量验证：

- 默认输出设备变化。
- 主音量读取。
- 静音状态读取。
- 连续按音量键时事件能否合并更新。

亮度验证：

- 是否存在公开且稳定的读取/监听路径。
- 内置屏与外接屏差异。
- 是否需要辅助功能权限。
- 是否只能捕获按键而无法得到真实亮度。

亮度实验若无法取得准确系统值，必须结论为 `passedWithLimitations` 或 `failed`，不得用自行累加的估算值冒充真实亮度。

#### LAB-05：文件与 AirDrop

验证：

- 文件进入面板热区时收到拖放事件。
- 只接受文件 URL，不接受任意脚本执行。
- 类型、大小、存在性和目标空间检查。
- 复制到实验容器，源文件不移动、不修改。
- 同名文件不覆盖。
- 从实验面板拖回 Finder。
- 单击打开实验副本。
- `NSSharingService.Name.sendViaAirDrop` 能打开系统分享流程。
- 用户取消 AirDrop 后实验副本保留。

安全规则：

- AirDrop 只打开系统选择界面，不自动发送。
- 测试清理只删除实验容器内、由实验创建的文件。
- 不使用真实敏感文件做测试。

---

## 八、Prompt 设计

不适用。

- 产品和第一阶段均无模型调用。
- 不创建 Prompt 文件。
- 不进行模型输出解析或结构校验。

---

## 九、最小验收界面

### 9.1 是否需要

需要。它是**一次性原生技术验证工具**，不是正式产品前端。

原因：窗口层级、鼠标焦点、拖放、Space、全屏和系统权限必须“看见并亲手操作”才能判断，单靠命令行或 JSON 不足以验收。

### 9.2 实验控制窗口

普通 `NSWindow`，包含五张实验卡：

- 屏幕几何。
- 面板行为。
- 音乐控制。
- 系统状态。
- 文件与 AirDrop。

每张卡只显示：

- 当前状态。
- “开始验证”按钮。
- 核心结果摘要。
- 限制或阻塞原因。
- “查看证据”入口。

### 9.3 顶部实验面板

只验证三种形态：

- Hidden。
- Collapsed。
- Expanded。

不实现正式颜色、动效、内容区、音乐卡片和文件架。

### 9.4 功能上限

实验界面不得：

- 被继续打磨成正式产品首页。
- 提前实现完整设置中心。
- 使用第三方动画或设计系统。
- 添加 PRD 之外的功能。
- 自动修改系统设置或权限。

---

## 十、测试要求

### 10.1 第一层：XCTest 自动化

#### 屏幕几何

- 给定左右辅助区域，能计算正确刘海宽高。
- 缺少辅助区域时返回悬浮模式。
- 负数、NaN、无限值和越界矩形被拒绝。
- Retina scale 不改变 points 语义。

#### 能力报告

- schema 版本正确。
- 状态枚举可编码/解码。
- 原子写入成功。
- 损坏 JSON 能恢复为空报告并保留错误证据。
- 并发写入被串行化。

#### 文件安全

- 非文件 URL 被拒绝。
- 不存在文件被拒绝。
- 同名文件生成安全新名称。
- 路径遍历名称被净化。
- 2GB 边界判断正确，无需真实创建 2GB 文件。
- 清理范围不能越出实验目录。

#### 系统数值

- 电量、音量、亮度标准化到 `0...1`。
- 越界和不可用值不进入 UI。
- 高频音量事件可合并而不丢失最终值。

#### 媒体 Adapter 契约

- 缺字段使用 `nil`，不伪造值。
- 未安装、权限拒绝、命令不支持映射为不同错误。
- 只允许白名单播放器标识。

### 10.2 第二层：真实 Mac 集成/人工冒烟

#### 屏幕与窗口

- 内置刘海屏真实检测。
- 无刘海外接屏降级。
- 普通桌面、多 Space、全屏应用、Stage Manager。
- 显示器插拔和主屏切换。
- 收起时不抢焦点，展开时鼠标可用。

#### 音乐

- Apple Music 播放一首非敏感测试曲目，验证能力矩阵。
- Spotify 安装后重复同一矩阵。
- 权限允许、拒绝和撤销各验证一次。
- 目标应用退出时实验应用不崩溃。

#### 系统状态

- 插入和拔出电源。
- 调整音量、静音、切换默认输出设备。
- 调整内置屏亮度并核对显示值是否准确。

#### 文件/AirDrop

- 拖入文本、图片、文件夹和同名文件。
- 验证源文件未改变。
- 拖出到 Finder。
- 打开 AirDrop 面板后取消，不实际发送即可证明系统流程能被唤起。

### 10.3 权限测试

每个需要 TCC 权限的实验覆盖：

1. 未请求。
2. 用户允许。
3. 用户拒绝。
4. 用户在系统设置中撤销。
5. 应用重新启动。

不得通过删除系统权限数据库等破坏性操作自动重置；需要重测时由测试者使用系统设置完成。

### 10.4 性能观察

第一阶段不做完整性能优化，但记录：

- 实验 App 冷启动时间。
- 面板显示/隐藏是否明显掉帧。
- 静默 5 分钟 CPU 与内存趋势。
- 高频音量事件是否造成主线程阻塞。
- 文件复制是否在主线程执行。

此阶段结果只用于发现架构风险，不代表已满足 PRD 最终性能验收。

### 10.5 测试结果真实性

- 自动化通过不能替代真实设备验证。
- 当前没有 Spotify、无刘海外接屏或完整 Xcode时，对应用例必须写“阻塞”，不能写“通过”。
- 亮度只能捕获按键但无法读取真实值时，不能写“亮度监听通过”。
- AirDrop 面板能打开不等于文件已成功发送；第一阶段只验证系统流程唤起。

---

## 十一、验收清单

以下是未来完成第一阶段后，产品经理可以照着操作的清单。当前尚未执行。

### 11.1 启动前

- [ ] 打开“关于本机”，确认正在使用带刘海的 MacBook。
- [ ] 确认 Apple Music 已安装；需要验收 Spotify 时确认 Spotify 已安装。
- [ ] 打开 `NotchFlowFeasibilityLab`，看到五张实验卡，而不是正式产品界面。
- [ ] 确认应用没有要求注册账号、填写 API Key 或上传数据。

### 11.2 屏幕几何

- [ ] 点击“屏幕几何 → 开始验证”。
- [ ] 内置屏结果显示“识别到物理刘海”，面板贴合屏幕顶部中央。
- [ ] 连接无刘海外接屏后重新验证，结果切换为“悬浮胶囊模式”。
- [ ] 拔掉外接屏，实验面板回到内置屏，没有留在屏幕外。

### 11.3 面板行为

- [ ] 点击“显示收起面板”，当前应用的输入焦点没有被强行抢走。
- [ ] 点击面板，面板可以展开并响应鼠标。
- [ ] 点击面板外部，面板按实验规则隐藏。
- [ ] 切换普通桌面和全屏应用，记录面板是否符合实验预期。
- [ ] 切换 Space，面板没有出现重复窗口或错位。

### 11.4 音乐

- [ ] 在 Apple Music 播放测试曲目。
- [ ] 点击“读取”，结果中的播放状态、歌名和艺人与播放器一致。
- [ ] 点击播放/暂停、上一首和下一首，播放器发生对应变化。
- [ ] 对无法读取的封面、进度或跳转能力，界面明确显示“不支持”，没有伪造数据。
- [ ] 拒绝自动化权限后，音乐实验提示权限问题，其他实验仍可使用。
- [ ] 安装 Spotify 后重复同样步骤；未安装时报告必须显示“阻塞”。

### 11.5 系统状态

- [ ] 插入和拔出电源，实验值与系统状态一致。
- [ ] 调整音量和静音，实验值连续更新且最终数值正确。
- [ ] 调整屏幕亮度，只有在能读到准确值时才标记通过。
- [ ] 若亮度不可稳定读取，报告明确说明限制，不显示估算数值。

### 11.6 文件与 AirDrop

- [ ] 将测试文本、图片和文件夹拖入实验面板。
- [ ] 实验副本创建成功，Finder 中原文件仍在原位置且内容未改变。
- [ ] 拖入同名文件后没有覆盖已有副本。
- [ ] 将实验副本拖回 Finder，可以正常打开。
- [ ] 点击 AirDrop，系统原生选择界面出现。
- [ ] 取消 AirDrop 后，暂存副本仍然存在。
- [ ] 点击“清理实验文件”后，只删除实验副本，不删除原文件。

### 11.7 阶段结论

- [ ] 五张实验卡都有结论和证据。
- [ ] 报告清楚区分“通过、有限制、失败、阻塞”。
- [ ] 没有用“开源项目做过”代替本机真实验证。
- [ ] 产品经理能够明确知道哪些能力进入下一阶段、哪些需要降级。

---

## 十二、风险与待确认项

### 12.1 当前阻塞项

| 阻塞项 | 影响 | 解除条件 |
|---|---|---|
| 完整 Xcode 未安装 | 无法创建、编译和测试 macOS App | 安装完整 Xcode并验证 `xcodebuild` |
| Spotify 未安装 | 不能完成 Spotify 真实能力矩阵 | 安装 Spotify 桌面客户端 |
| 当前未发现无刘海外接屏 | 无法完成悬浮胶囊真实外接屏验证 | 准备无刘海外接显示器 |

这些阻塞不影响本次文档交付，但会阻止第一阶段被判定为全部完成。

### 12.2 技术风险

| 风险 | 判定方式 | 预设处理 |
|---|---|---|
| Apple Music/Spotify 能力不一致 | 分播放器能力矩阵 | Adapter 分离，逐项降级，不承诺统一字段 |
| Apple Events 权限影响分发 | 沙盒开启的真实权限测试 | 记录 entitlements 与审核影响，发布阶段再裁决 |
| 亮度没有稳定公开监听路径 | 对照系统真实值连续测试 | 不显示估算值；按 PRD 标记不可用或降级 |
| 面板与全屏/Stage Manager 冲突 | 多场景实机矩阵 | 窗口层与普通设置窗口分离，记录可用 collectionBehavior |
| AirDrop 服务不可用 | 唤起系统服务并验证取消/错误 | 保留文件，显示恢复建议 |
| 沙盒拖入权限跨重启失效 | 复制到容器后重启验证 | 正式产品以容器副本为准，不依赖源路径 |

### 12.3 需要产品经理决定的问题

无。

如果实验结果触发以下情况，才需要重新确认：

- Spotify 无法达到 PRD 的 P0 控制能力，需要从首版完整支持降级。
- 亮度只能依赖不适合分发的非公开能力，需要从 P0 移出或仅保留按键提示。
- App Sandbox 与核心音乐/文件能力发生不可调和冲突，影响 Mac App Store 路线。

---

## 十三、交接给下一阶段

### 13.1 本阶段通过后应交付的可复用能力

- 已验证的 `ScreenGeometryProbe` 计算规则。
- 已验证的 `NSPanel` 属性和多屏重新定位策略。
- Apple Music/Spotify 能力矩阵与 Adapter 契约。
- 电源、音量和亮度的可用数据来源。
- 文件校验、容器复制、拖出和 AirDrop 的安全路径。
- 统一错误类型、日志边界和能力报告。

### 13.2 下一阶段允许复用什么

PRD 阶段 1“交互底座”可以复用：

- 屏幕几何 Service 的已验证核心。
- 面板 Controller 的已验证配置。
- 系统能力的 Protocol/Adapter 契约。
- 纯逻辑 XCTest。

### 13.3 下一阶段不得直接继承什么

- 实验 Dashboard 视觉。
- 三态实验面板内容。
- 调试按钮和人工触发入口。
- 临时 Bundle ID 和实验报告 UI。
- 为实验方便添加但不适合正式产品的权限或日志。

### 13.4 下一步动作

当前只完成文档。产品经理确认《技术适配声明》和本文档后，下一步才是：

1. 安装完整 Xcode。
2. 补齐 Spotify 与无刘海外接屏测试条件。
3. 明确授权开始第一阶段开发。

未获得“开始开发”的明确指令前，不创建工程或代码。

---

## 十四、参考资料

- [NotchFlow PRD v1.0](./PRD-MacBook-Notch-Island-v1.0.md)
- [NotchFlow 技术适配声明 v1.0](./技术适配声明-NotchFlow-v1.0.md)
- [AI Agent 产品 Vibe Coding 通用技术栈手册 V2.1](./AI产品Vibe%20Coding通用技术栈手册(1).md)
- Apple Developer — `NSScreen.auxiliaryTopLeftArea`：  
  https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc
- Apple Developer — `NSPanel`：  
  https://developer.apple.com/documentation/appkit/nspanel
- Apple Developer — Window Collection Behavior：  
  https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct
- Apple Developer — Apple Events Entitlement：  
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events
- Apple Developer — `NSSharingService`：  
  https://developer.apple.com/documentation/appkit/nssharingservice
- Apple Developer — App Sandbox 文件访问：  
  https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
