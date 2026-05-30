# notchwow 架构说明

## 1. 项目定位

`notchwow` 是一个 SwiftPM 管理的 macOS 原生可执行应用。AppKit 负责屏幕、窗口层级、目录打开和事件监控；SwiftUI 负责工作台界面；vendored `swift-markdown-engine` 负责 Markdown 编辑器能力。

SwiftPM 产品名和主 target 均为 `notchwow`：

```text
Package.swift
└── executable product: notchwow
    └── target: notchwow
```

## 2. 启动链路

1. `Sources/notchwow/main.swift` 创建 `NSApplication` 并注册 `AppDelegate`。
2. `AppDelegate.applicationDidFinishLaunching` 创建 `NotchPanelController`、状态栏图标和菜单。
3. `NotchPanelController` 作为 composition root，持有状态 Store、命令 Runner、热区面板和抽屉面板。
4. `NotchPanelController.rebuildContent` 把依赖注入 `NotebookView`。
5. 鼠标进入刘海热区后，控制器展开 SwiftUI 工作台；鼠标离开后延迟折叠。

## 3. UI 分层

### AppKit 层

| 文件 | 职责 |
| --- | --- |
| `AppDelegate.swift` | 应用生命周期、菜单栏、全局快捷菜单。 |
| `NotchPanelController.swift` | 刘海热区、窗口展开折叠、鼠标轮询、Store 装配。 |
| `SettingsPopoverController.swift` | 设置弹窗窗口与点击外部关闭逻辑。 |
| `NotchGeometry.swift` | 目标屏幕、刘海测量、面板尺寸。 |
| `TerminalAppBridge.swift` | 使用 `osascript` 在 Terminal.app 打开指定目录。 |

### SwiftUI 层

`NotebookView.swift` 是工作台 UI 的集中入口。当前可见模式如下：

| 模式 | 标题 | 核心能力 |
| --- | --- | --- |
| Markdown | `MD` | 笔记、附件、Markdown 工具栏、AI 修改、AI 问答。 |
| Shell | `Shell` | Shell 工作区脚本和命令输出。 |
| Python | `Py` | Python 文件、Conda 环境、持久 REPL。 |
| AppleScript | `AS` | AppleScript 文件和单行命令。 |
| Launchd | `Jobs` | plist 编辑、加载、卸载、AI 生成。 |

### 状态与存储层

| 文件 | 职责 |
| --- | --- |
| `NoteStore.swift` | Markdown 文件发现、切换、保存、外部变更同步。 |
| `CodeFileStore.swift` | Python 和 AppleScript 文件的通用存储。 |
| `ShellWorkspaceStore.swift` | Shell workspace、输入、脚本和 transcript。 |
| `WorkspaceDirectoryStore.swift` | 用户可编辑的工作目录和持久化。 |
| `LocalImageStore.swift` | Markdown 附件复制、manifest、图片解析。 |
| `LaunchdJobStore.swift` | plist 扫描、保存、加载、卸载、孤儿服务清理。 |
| `AppSettingsStore.swift` | 触发方式、百炼 API Key、AI 模型。 |

### 执行与外部系统层

| 文件 | 职责 |
| --- | --- |
| `CommandRunner.swift` | 使用 `/bin/zsh -lc` 执行 Shell 或 `osascript` 命令。 |
| `PythonReplRunner.swift` | 维护 Python 子进程，通过 JSON 行协议执行输入和文件。 |
| `CondaEnvironmentStore.swift` | 发现 Conda 环境，生成 Python 启动配置。 |
| `MarkdownAIEditStore.swift` | 调用百炼兼容接口生成 Markdown 局部替换。 |
| `MarkdownAIChatStore.swift` | 基于当前 Markdown 内容进行问答。 |
| `ScriptAIEditStore.swift` | 为 Shell、Python、AppleScript 生成可预览、拒绝或应用的完整脚本提案。 |
| `LaunchdAIAgent.swift` | 根据现有脚本和任务上下文生成 plist。 |
| `BailianChatClient.swift` | 百炼兼容接口的统一 endpoint、鉴权、超时和错误处理。 |

## 4. 默认目录

默认根目录由当前用户 Home 动态计算，不再写死账户名：

```text
~/keyoti/
├── mds/
│   └── attachments/
├── pys/
│   └── transcript.log
├── shs/
│   ├── workspaces/
│   ├── workspace-inputs/
│   └── workspace-scripts/
├── applescripts/
└── launchds/
```

另外有两个可选集成，均可在 Settings 中覆盖默认值：

| 路径 | 用途 |
| --- | --- |
| `~/Desktop/Benshell` | Shell 初始化和命令目录。 |
| `~/miniforge3` | Conda 与默认 Python 路径。 |

## 5. 关键数据流

### Markdown

`MarkdownNoteEditor` -> `NativeTextViewWrapper` -> `NoteStore.updateText` -> Markdown 文件。

粘贴附件时，`LocalImageStore` 把文件复制到 `attachments/`，记录 manifest，并向文档插入 wiki 风格引用。

### Shell

`ShellInputToolbar` -> `CommandRunner.run` -> `/bin/zsh -lc` -> transcript 文件 -> `OutputView`。

### Python

`PythonCommandToolbar` -> `PythonReplRunner` -> Conda Python 子进程 -> JSON 行协议 -> `OutputView`。

### Launchd

`LaunchdPane` -> `LaunchdJobStore` -> plist 文件 -> `/bin/launchctl bootstrap|bootout`。

## 6. 安全边界

- Shell、Python、AppleScript 和 `launchd` 都会执行用户输入，应用不应接收不可信脚本。
- 工作区删除操作统一使用 macOS 废纸篓，并在 UI 中二次确认。
- Markdown、脚本和 Shell workspace 的磁盘写入错误会通过顶部警告徽标反馈给用户。
- 从 Settings 在 Terminal 打开目录会触发 macOS Apple Events 权限提示。
- AI 功能会把笔记内容或任务上下文发送到百炼兼容接口。
- API Key 保存在 macOS Keychain；旧版 `UserDefaults` 明文会在首次启动时迁移并删除。
- `LaunchdJobStore` 会自动清理缺少本地 plist 的 `com.notchwow.*` 已加载任务。修改此策略前需要确认产品语义。

## 7. Vendored MarkdownEngine

`Vendor/swift-markdown-engine` 是内置依赖，提供：

- TextKit 2 编辑器包装。
- Markdown tokenization 与样式。
- Wiki links、附件、任务 checkbox。
- 代码块高亮和 LaTeX bridge。

业务层通过 `MarkdownEditorServices` 注入图片和 LaTeX 实现，避免 MarkdownEngine 反向依赖应用状态。
