# 第七阶段技术开发文档：Paimon Pal 本地生产力工作台 v1.0

更新日期：2026-09-02

对应版本：0.4.0 (10)

阶段结论：代码实现与自动验证完成，麦克风、本机语音识别和摄像头保留安装版人工补验。

## 1. 阶段目标

把参考开源项目 TO-DO Panel 中适合刘海交互的生产力能力，以原生 SwiftUI/AppKit 方式合入 Paimon Pal，不引入 Electron 运行时，不破坏现有派蒙、Apple Music、文件架、系统状态和计时器。

## 2. 产品入口

- 菜单栏和刘海面板均可打开“Paimon Pal 工作台”。
- 工作台是普通可移动、可缩放、非置顶窗口，不长期遮挡用户当前应用。
- 左侧导航包含工作台、待办、随笔记、链接、剪贴板、录音、镜子和保险箱。
- Bento 首页模块可隐藏、恢复和排序，至少保留一个可见模块。

## 3. 实现模块

### 3.1 首页与快捷启动

- 首页聚合音乐、计时、系统、文件、待办、笔记、应用启动、AI 任务、录音和镜子。
- 快捷启动显示当前/最近/常用应用，通过 `NSWorkspace` 打开或激活，不注入其他进程。

### 3.2 待办与随笔记

- 待办支持分类、截止时间、完成与删除；排序优先未完成且截止更早的项目。
- 只在系统通知权限已授予时安排本地提醒，不为新增待办强制弹权限。
- 随笔记保存 Markdown 原文，标题可由首个有效文本行自动生成，也可手动修改。

### 3.3 链接与剪贴板

- 链接只接受公开 `http/https` 地址，拒绝 localhost、回环、私有网段、本机文件和非 Web scheme。
- 剪贴板历史默认关闭；开启前内容不回读，仅记录新的纯文本，最多 80 条。
- 疑似密码、Token、私钥、API Key 和超长文本被过滤。应用内复制与保险箱复制会同步更新 change count，不会被历史二次收集。

### 3.4 录音、镜子与保险箱

- 录音仅在主动点击后申请麦克风，保存 M4A 和 JSON 索引；停止后尝试中文设备端转写。
- 录音删除使用 macOS 废纸篓，不直接不可恢复删除。
- 镜子仅显示 `AVCaptureSession` 实时预览，不录制；离开页面会调用 `stopRunning()`。
- 保险箱使用 macOS Keychain，可用等级为 `AfterFirstUnlockThisDeviceOnly`，不写入工作台 JSON。

### 3.5 AI 任务完成提醒

- 使用 `NWListener` 只绑定 `127.0.0.1:43821`。
- 仅允许 `POST /notify/codex|claude|gpt`，请求体上限 32 KB，其他 method/source 拒绝。
- 支持 `taskID` 和 `task_id`；完成事件进入工作台卡片、刘海 HUD 和派蒙成功反馈。
- 命令行辅助脚本：`scripts/notify_paimon_pal.sh <codex|claude|gpt> <title> [project] [task_id]`。

### 3.6 派蒙工具扩展

- 确定性路由支持“新建待办”和“记一条随笔”，不将普通聊天误判为工具调用。
- 支持打开工作台、待办、随笔记、链接、剪贴板、录音、镜子和保险箱页。

## 4. 数据与边界

- 工作台快照：`Application Support/Paimon Pal/productivity/workspace-v1.json`。
- 录音：`Application Support/Paimon Pal/recordings/`。
- 保险箱：macOS Keychain，不使用普通文件保存密文。
- 任务提醒：本机回环端口，不暴露局域网。
- 不引入远程同步、不引入账号系统、不引入第三方分析 SDK。

## 5. 开发结果

- 分支：`codex/productivity-workspace`。
- 自动测试：147/147 通过。
- 真实 UI：8 个工作台页面可访问；待办新增/保存/删除闭环通过。
- 真实回调：Codex 任务通知返回 `202 Accepted`，工作台显示事件；非白名单来源返回 404，超大请求返回 400。
