# BenBenBen 架构说明

## 1. 产品边界

`BenBenBen` 是由 SwiftPM 管理的 macOS 26 原生应用。它有两个入口：

- SwiftUI 主窗口：个人 Codex 会话、知识、任务、工具与自动化工作台。
- AppKit 刘海 `NSPanel`：Ben龙快速入口、Agent 状态和审批提醒；无刘海时回退为顶部浮动入口。

原始个人资料只保存在 `~/keyoti`；派生数据库只保存搜索索引和 UI 元数据。Codex 会话正文由 app-server thread API 管理。

SwiftPM 身份统一为：

```text
Package.swift
├── executable product: BenBenBen
│   └── target: BenBenBen
└── executable product: BenBenBenLoginHelper
    └── target: BenBenBenLoginHelper
```

App bundle 为 `BenBenBen.app`，Bundle ID 为 `io.github.benjaminisgood.benbenben`。

## 2. 启动与 Scene

1. `Sources/BenBenBen/App/BenBenBenApp.swift` 通过 SwiftUI `@main App` 启动。
2. `WindowGroup("BenBenBen", id: "main")` 提供主工作台。
3. `Settings` 提供 Codex、语音、目录、权限和 Runtime 设置入口。
4. `MenuBarExtra` 在主窗口关闭后继续提供打开 App、Ben龙和退出入口。
5. `AppDelegate` 只承担必要的 AppKit 生命周期衔接；`AppModel` 持有应用级导航和模块入口。
6. `NotchPanelController` 只负责刘海面板、屏幕几何与展开/收起，不再作为全部状态的唯一 composition root。

普通启动打开主窗口并保持 Ben龙驻留。关闭最后一个主窗口不会终止 App。

启用登录启动后，`Contents/Library/LoginItems/BenBenBenLoginHelper.app` 以
`--companion-only` 启动主 App：只显示 Ben龙与 MenuBarExtra，不自动打开主工作台；用户从菜单或 Ben龙进入主窗口时再切回普通 App activation policy。

## 3. 模块分层

### App 与主窗口

| 位置 | 职责 |
| --- | --- |
| `App/BenBenBenApp.swift` | Scene、Commands、Settings、MenuBarExtra。 |
| `App/AppModel.swift` | 应用导航、主窗口/Ben龙入口、模块模型装配。 |
| `App/WorkbenchEnvironment.swift` | 现有 Markdown、Scripts、Python、AppleScript、Jobs store 的统一生命周期。 |
| `Views/Main/MainWindowView.swift` | `NavigationSplitView`、Liquid Glass 首页与 Inspector。 |
| `NotchPanelController.swift` | AppKit 刘海/浮动 panel、屏幕几何和事件桥接。 |

主窗口路由包含 Home、Today、Inbox、Agents、Knowledge、Scripts、Python 和 Automations。现有 `NotebookView` 继续承载成熟的工作台视图，逐步由模块模型接入主窗口。

### Agent

`Sources/BenBenBen/Agent/` 定义稳定的 App 内部边界：

| 类型 | 职责 |
| --- | --- |
| `AgentRuntime` | 启动/停止、账户、线程、turn、interrupt、审批和 `AsyncStream<AgentEvent>`。 |
| `CodexExecutableDetector` | 发现用户选择或 PATH 中的 Codex executable，并显示版本。 |
| `CodexProcessActor` | 长驻运行 `codex app-server --stdio`，管理 JSONL request/response、stderr 与重启。 |
| `AgentStore` | 把线程、delta、Diff、命令输出、token、审批和错误投影到 SwiftUI。 |

首版使用稳定 app-server 协议，不依赖 realtime、dynamic tools 等实验 API。解码器允许服务端增加未知字段；未知事件会记录而不是导致进程崩溃。Codex 登录由所选 executable 自己管理，App 不读取或复制 `auth.json`。

已验证协议固定在 `ProtocolSchemas/Codex-<version>/`。版本变化时 App 显示契约警告；升级基线必须先重新生成 schema 并跑契约测试。

### 个人知识与任务

`Sources/BenBenBen/Personal/` 负责 `~/keyoti` 的只读索引和受控任务写入：

| 类型 | 职责 |
| --- | --- |
| `WorkspaceRegistry` | Markdown、Shell、Python、AppleScript 和 launchd 的唯一根目录注册表。 |
| `PersonalSearchIndex` | SQLite FTS5 派生索引、mtime/内容哈希增量刷新、来源路径和行号。 |
| `PersonalTaskService` | 识别 checkbox、`TODO:`/`待完成:`、日期和标签；执行带行哈希校验的完成操作。 |
| `PersonalWorkspaceStore` | SwiftUI 查询、刷新、Inbox 捕获和冲突错误状态。 |

快速捕获写入 `~/keyoti/mds/Inbox.md`。任务更新前会核对原行哈希并尊重系统级文件锁；外部修改或锁定时拒绝覆盖。

### 现有工作台

| 文件 | 职责 |
| --- | --- |
| `NoteStore.swift` | Markdown 文件发现、保存、外部同步。 |
| `CodeFileStore.swift` | Python 与 AppleScript 文件存储。 |
| `ShellWorkspaceStore.swift` | Shell workspace、脚本和 transcript。 |
| `ScriptsModuleState.swift` | Scripts 搜索、命令和语言状态。 |
| `FilePermissionLockStore.swift` | UI 与文件系统双层写保护。 |
| `TerminalAppBridge.swift` | 在 Terminal.app 打开目录或运行用户确认的命令。 |
| `PythonReplRunner.swift` | 管理 Python 子进程及 JSON 行协议。 |
| `LaunchdJobStore.swift` | plist 扫描、保存、加载、卸载与状态。 |

`Vendor/swift-markdown-engine` 继续提供 TextKit 2、Markdown、wiki links、附件、任务 checkbox、代码高亮和 LaTeX 能力。

## 4. Runtime

版本化源位于仓库 `Runtime/`，并作为 `BenBenBen.app/Contents/Resources/Runtime` 打包。安装器把版本复制到：

```text
~/Library/Application Support/BenBenBen/Runtime/
├── releases/<version>/
└── current -> releases/<version>
```

`current` 通过原子符号链接切换。受管 `~/.zshrc` 区块把 Runtime `bin` 加入 PATH，并加载同一份 `Benshell/zsh/init.zsh`。

`Runtime/manifest.json` 的 action 数据契约为：

```text
id / title / summary / executable / arguments / cwd / risk / inputSchema
```

`executable` 必须是 Runtime 内相对路径，`arguments` 是固定数组。`benbenben tools run` 不接受额外 argv；非 `read` action 必须显式审批。

Runtime 安装不会隐式运行 Brewfile、macOS defaults、Git sync/push、服务启动或端口清理。

`Runtime/bin/benbenben-mcp` 是无第三方依赖的 stdio MCP helper，提供：

- `search_knowledge`、`read_document`、`recent_activity`
- `list_workflows`、`workflow_status`、`run_workflow`
- `list_jobs`、`job_status`、`run_job`

它不会接受任意 executable 或 argv。只读 manifest action 可执行；非只读 workflow 与 `run_job` 只返回 `approval_required`，由原生 App 完成审批。

## 5. Ben龙与语音

`MascotState` 包含 idle、listening、thinking、working、waitingApproval、success、error 和 sleep。状态由 Codex/语音事件驱动；SwiftUI 只负责呼吸与轻跳动画。九格视觉源还包含独立 logo pose，切片后作为八态透明 sprite 与 1024 App 图标。

`VoiceInteractionController` 使用 Speech 与 AVFoundation：长按 250 ms 后录音、松开听写、两秒可取消倒计时后发送；不常驻监听。只有语音发起的短回复可按设置朗读，随时可停止。

## 6. 默认目录

```text
~/keyoti/
├── mds/
│   ├── Inbox.md
│   └── attachments/
├── pys/
├── shs/
│   ├── workspace-scripts/
│   ├── workspaces/
│   └── workspace-inputs/
├── applescripts/
└── launchds/
```

`~/keyoti` 始终是个人文件的唯一真相，App 不自动搬迁或删除它。

## 7. 安全与审批

- 读取与搜索可自动执行；任何文件写入先展示 Diff。
- 命令、Jobs、删除、Git push 和外发动作进入审批。
- Agent thread 默认使用用户选中的项目 cwd；个人会话默认 `/Users/ben/keyoti`。
- 默认 sandbox 为 workspace-write、按需审批，不授予整个 Home unrestricted 权限。
- 文件删除进入废纸篓并二次确认。
- API Key 保存在 macOS Keychain；百炼仅作为 Advanced 中的旧版兼容 Provider。
- Runtime action 只能引用 manifest 中的固定 action ID。

### launchd 双前缀兼容

- 新建 Job 使用 `com.benbenben.*`。
- `com.notchwow.*` 是旧版兼容前缀，继续显示并保持当前 loaded/unloaded 状态。
- BenBenBen 不自动重命名、卸载或删除旧 `com.notchwow.*` Job。
- 新前缀的孤儿清理逻辑不得扩展到旧前缀。

## 8. 迁移兼容层

为了保留原 notchwow 与 notchNotes 用户数据：

- 新偏好键使用 `benbenben.*`，同时读取 `notchwow.*`、`notchNotes.*` 等已知旧键。
- 新 Keychain service 为 `io.github.benjaminisgood.benbenben`。旧 service 仅在 Advanced 中由用户明确点击导入，避免不同签名 ACL 在启动时弹窗；复制后不删除旧 item。
- `benshell`、`notchwow`、`nw` 命令继续转发到统一 `benbenben` CLI。
- 旧 `/Users/ben/Desktop/Benshell`、旧仓库和旧 App bundle 作为迁移备份保留到验收结束。

兼容字符串是刻意保留的数据契约，品牌清理不能机械删除它们。
