# NotchFlow

NotchFlow 是一款原生 macOS 刘海交互工具，把 MacBook 屏幕顶部的物理刘海扩展为状态提示和快捷操作入口。

当前版本：`0.2.0 (1)`，处于本地 MVP 验收阶段，尚未完成 Developer ID 正式签名和苹果公证。

## 当前功能

- Apple Music：显示歌曲、歌手、封面和进度，支持播放/暂停、上一首、下一首与拖动进度。
- 文件架：复制并暂存主动拖入或选择的文件，支持导出、拖回 Finder、AirDrop 和手动清理。
- 系统状态：显示电池、电源、音量和静音变化。
- 计时器：支持单倒计时、暂停、继续、结束提醒和重启恢复。
- 设置：功能开关、菜单栏入口、暂停、登录启动、权限状态、显示器和全屏策略。

Spotify 已暂缓，不属于当前 MVP 验收范围。屏幕亮度没有面向普通第三方 App 的稳定公开通用接口，因此不显示猜测数值。

## 使用方法

1. 鼠标移到刘海，查看轻量预览。
2. 点击刘海展开或收起面板。
3. 右键点击刘海，打开设置或完整功能窗口。
4. 也可以使用菜单栏里的 NotchFlow 图标进入设置、暂停或退出。

首次启动会显示使用与隐私说明，但不会自动申请权限。Apple Music 自动化和通知权限只在使用相关功能时按需申请。

## 文件安全

- NotchFlow 只复制你主动拖入或选择的文件，Finder 原文件不会被移动或删除。
- 暂存副本位于 App Sandbox 的 Application Support 目录。
- 暂存副本默认保留 24 小时，也可以在文件架中提前删除。
- 删除、过期清理和“全部清理”只处理 NotchFlow 自己的暂存副本。

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

- XCTest：66 项通过（加入首次启动状态测试后）。
- 静默 CPU：当前实机约 0.66%。
- 静默内存：当前实机约 29.6 MB。
- 本机从启动到刘海可见：约 0.45 秒。

这些数字来自当前 Apple Silicon 刘海屏 MacBook Pro，不代表所有机型与系统版本。
