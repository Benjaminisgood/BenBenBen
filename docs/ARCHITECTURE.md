# BenBenBen 架构

## 产品路径

```text
BenBenBenApp
├── AppModel
│   ├── AgentStore -> codex app-server
│   ├── MascotModel / VoiceInteractionController / ScreenContextMonitor
│   ├── NotchPanelController -> NotchCompanionView
│   ├── AgentArtifactWindowController
│   └── AgentTaskWindowController
├── Settings scene
└── MenuBarExtra
```

当前产品只有两类界面、六个独立协作窗口：

1. 刘海伙伴：固定为 `186 × 140` 的纯黑区域，不再区分折叠和展开态。点击龙开始/暂停持续语音，不提供文字输入、新任务、发送或屏幕开关按钮。
2. 五个多标签文件共同窗口：HTML、Python、Markdown、Shell/AppleScript、launchd plist；另有一个左历史、右细则的单实例任务窗口。

不存在第二套主窗口、旧诊断页面或按文件类型复制的编辑工作台。

## Codex 协议

`CodexProcessActor` 只发送当前 `initialize`、`thread/*` 和 `turn/*` 接口，并处理当前 item approval 请求。`AgentStore` 把协议事件投影成线程、活动、消息、计划、token 与审批状态。

`ProtocolSchemas/Codex-<version>/` 保存已验证的 app-server schema 快照。升级 Codex 基线时重新生成快照并运行协议测试。

## 文件共同窗口

`AgentArtifactKind` 定义每类文件的当前根目录和扩展名。窗口直接扫描文件系统，不维护第二份业务数据库。每个文件窗口维护一组打开标签；语音提交或运行中引导会把所有可见文件窗口的全部标签路径加入 operating contract，并标记聚焦窗口和选中标签。任务前后快照会把同类的多个新建或更新产物同时打开为标签页。

`AgentTaskWindowController` 只维护一个任务窗口。选择历史任务会同步 `AgentStore.selectedThreadID`；未明确说“新任务”时，下一段语音继续这个线程。`request_user_input` 和审批会按活跃程度自动打开任务窗口，选择既可点击，也可直接口头回答。

## Runtime

`Runtime/` 是版本化、可原子安装的运行目录：

- `bin/benbenben`：完整 CLI。
- `bin/bbb`：当前短别名。
- `bin/benbenben-mcp`：MCP helper。
- `Benshell/`：当前 shell 环境和固定项目控制器。
- `manifest.json`：可执行 action 白名单。

Runtime 不接受模型拼接的任意 argv。非只读 action 必须审批。

## 数据与安全边界

原始文件只存放在设置页配置的永久内容目录中，默认为 `~/keyoti`。新 launchd Label 使用 `com.benbenben.*`；其他前缀不属于应用管理面。现有 `com.notchwow.*` Job 受仓库安全约定保护，不自动改名、卸载或删除。
