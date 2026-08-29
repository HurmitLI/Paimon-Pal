# Paimon Pal（PP）

Paimon Pal 是一款带本地派蒙桌宠的原生 macOS 刘海交互工具，简称 PP。它把 MacBook 屏幕顶部的物理刘海扩展为陪伴、状态提示和快捷操作入口。

当前版本：`0.3.0 (3)`，处于个人课程作业验收阶段，尚未完成 Developer ID 正式签名和苹果公证。

为兼容已有设置与本地数据，Xcode 工程名、Bundle ID 和沙盒内部目录仍保留旧技术名称 `NotchFlow`；这些内部名称不影响用户看到的 Paimon Pal 品牌。

## 当前功能

- Apple Music：显示歌曲、歌手、封面和进度，支持播放/暂停、上一首、下一首与拖动进度。
- 文件架：复制并暂存主动拖入或选择的文件，支持导出、拖回 Finder、AirDrop 和手动清理。
- 系统状态：显示电池、电源、音量和静音变化。
- 计时器：支持单倒计时、暂停、继续、结束提醒和重启恢复。
- 桌面宠物：从物理刘海旁出现，支持待机、点击、聆听、回复和成功反馈动画。
- 本地陪伴：内置 1.7B 级 4-bit 本地模型，支持简短连续聊天、最近 6 条会话上下文和计时/窗口工具调用。
- 设置：功能开关、菜单栏入口、暂停、登录启动、权限状态、显示器和全屏策略。

Spotify 已暂缓，不属于当前 MVP 验收范围。屏幕亮度没有面向普通第三方 App 的稳定公开通用接口，因此不显示猜测数值。

桌宠形象素材仅用于个人学习、课程作业和非商业演示，不包含公开分发或商业使用授权。

## 使用方法

1. 鼠标移到刘海，查看轻量预览。
2. 点击刘海展开或收起面板。
3. 右键点击刘海，打开设置或完整功能窗口。
4. 也可以使用菜单栏里的 Paimon Pal 图标进入设置、暂停或退出。

首次启动会显示使用与隐私说明，但不会自动申请权限。Apple Music 自动化和通知权限只在使用相关功能时按需申请。

## 文件安全

- Paimon Pal 只复制你主动拖入或选择的文件，Finder 原文件不会被移动或删除。
- 暂存副本位于 App Sandbox 的 Application Support 目录。
- 暂存副本默认保留 24 小时，也可以在文件架中提前删除。
- 删除、过期清理和“全部清理”只处理 Paimon Pal 自己的暂存副本。

完整说明见 [PRIVACY.md](PRIVACY.md)。

## 本地开发与验证

环境要求：

- macOS 14 或更高版本
- Xcode 和 Apple Clang/Swift 工具链

运行测试：

```bash
xcodebuild test -project NotchFlow.xcodeproj -scheme NotchFlow \
  -destination 'platform=macOS'
```

构建 Apple Silicon Release：

```bash
xcodebuild build -project NotchFlow.xcodeproj -scheme NotchFlow \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO
```

未完成 Developer ID 签名和公证的构建只适合本机开发验证，不能当作公开发布包。

## 文档

- [CHANGELOG.md](CHANGELOG.md)：版本说明
- [PRIVACY.md](PRIVACY.md)：隐私、权限和本地数据边界
- [SUPPORT.md](SUPPORT.md)：支持范围、已知问题和待补设备矩阵
- [PRD-MacBook-Notch-Island-v1.0.md](PRD-MacBook-Notch-Island-v1.0.md)：产品需求文档

## 当前验证结果

- XCTest：85 项通过。
- 内置本地模型可正常加载并生成简体中文回复。
- 桌宠动画、连续聊天、上下文清理、计时工具与窗口工具均已完成本机人工验证。
- 0.3.0 加入按需加载的本地模型后，静默与推理阶段性能仍需分别记录，旧版性能数字不再直接沿用。

上述结果来自当前 Apple Silicon 刘海屏 MacBook Pro，不代表所有机型与系统版本。
