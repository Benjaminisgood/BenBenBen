# BenBenBen 架构

## 产品路径

```text
BenBenBenApp
├── AppModel
│   ├── AgentStore -> codex app-server
│   ├── MascotModel / VoiceInteractionController / ScreenContextMonitor
│   ├── NotchPanelController -> NotchCompanionView
│   └── AgentArtifactWindowController
├── Settings scene
└── MenuBarExtra
```

当前产品只有两类界面：

1. 刘海伙伴：展示龙、任务进度、审批、文本/语音输入和屏幕上下文状态。
2. 五个共同窗口：HTML、Python、Markdown、Shell/AppleScript、launchd plist。

不存在第二套主窗口、旧诊断页面或按文件类型复制的编辑工作台。

## Codex 协议

`CodexProcessActor` 只发送当前 `initialize`、`thread/*` 和 `turn/*` 接口，并处理当前 item approval 请求。`AgentStore` 把协议事件投影成线程、活动、消息、计划、token 与审批状态。

`ProtocolSchemas/Codex-<version>/` 保存已验证的 app-server schema 快照。升级 Codex 基线时重新生成快照并运行协议测试。

## 文件共同窗口

`AgentArtifactKind` 定义每类文件的当前根目录和扩展名。窗口直接扫描文件系统，不维护第二份业务数据库。任务前后快照用于自动显示新建或更新的产物。

## Runtime

`Runtime/` 是版本化、可原子安装的运行目录：

- `bin/benbenben`：完整 CLI。
- `bin/bbb`：当前短别名。
- `bin/benbenben-mcp`：MCP helper。
- `Benshell/`：当前 shell 环境和固定项目控制器。
- `manifest.json`：可执行 action 白名单。

Runtime 不接受模型拼接的任意 argv。非只读 action 必须审批。

## 数据与安全边界

原始文件只存放在 `~/keyoti` 的当前目录中。新 launchd Label 使用 `com.benbenben.*`；其他前缀不属于应用管理面。现有 `com.notchwow.*` Job 受仓库安全约定保护，不自动改名、卸载或删除。
