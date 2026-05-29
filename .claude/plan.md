# Plan: Term 模块改造 — launchd 自动化任务管理

## 概述

将 Term 模块改造为 macOS launchd 自动化任务管理中心：
- 管理 plist 配置文件，通过 launchd 调度 shell/python 脚本在 Terminal.app 中执行
- 右上角搜索：检索所有 plist 配置文件，点击查看/编辑内容
- 左下角 tab picker：显示当前已加载（运行中）的 launchd job，点击查看其 plist
- 输入框：自然语言让 AI 帮写 plist 配置文件
- 中间区域：显示选中 plist 的内容（可编辑）

## 存储目录

```
/Users/ben/keyoti/launchd/          ← 新增目录
├── com.notchwow.health-check.plist
├── com.notchwow.backup.plist
└── ...
```

plist 中通过 `ProgramArguments` 指定执行 shell/python 脚本（来自 shs/ 或 pys/ 目录），
通过 `StartInterval` 或 `StartCalendarInterval` 设定调度时间。

## 架构设计

### 新增文件

#### 1. `LaunchdJobStore.swift`

```swift
struct LaunchdJob: Identifiable, Equatable {
    let id: String          // plist 文件名（不含 .plist）
    let label: String       // plist 中的 Label 字段
    let plistURL: URL
    let content: String     // plist 原始文本
    let isLoaded: Bool      // 是否已 launchctl load
    let modifiedAt: Date
}

@MainActor
final class LaunchdJobStore: ObservableObject {
    @Published var jobs: [LaunchdJob] = []          // 所有 plist 文件
    @Published var loadedLabels: Set<String> = []   // 当前已加载的 job labels
    @Published var selectedJobID: String?
    @Published var editingContent: String = ""
    @Published var searchQuery: String = ""

    func refresh()                    // 扫描目录 + launchctl list
    func load(_ job: LaunchdJob)      // launchctl load
    func unload(_ job: LaunchdJob)    // launchctl unload (bootout)
    func save(_ content: String, for job: LaunchdJob)  // 写回 plist
    func createJob(filename: String, content: String)  // 新建 plist
    func deleteJob(_ job: LaunchdJob) // 删除 plist 文件
}
```

核心逻辑：
- `refresh()`: 扫描 `WorkspacePaths.launchdRoot` 下所有 .plist 文件 + 执行 `launchctl list` 获取已加载 jobs
- `load()`: `launchctl load <plist_path>` 或 `launchctl bootstrap gui/<uid> <plist_path>`
- `unload()`: `launchctl unload <plist_path>` 或 `launchctl bootout gui/<uid>/<label>`
- 定时 refresh（每 5 秒），检测 job 状态变化

#### 2. `LaunchdAIAgent.swift`

```swift
@MainActor
final class LaunchdAIAgent: ObservableObject {
    @Published var input: String = ""
    @Published var lastMessage: String = ""
    @Published var isRunning: Bool = false

    func submit(settings: AppSettingsStore, context: LaunchdAIContext)
}

struct LaunchdAIContext {
    let existingJobs: [LaunchdJob]
    let availableScripts: [String]   // shs/ + pys/ 中的脚本列表
    let selectedJob: LaunchdJob?
}
```

- 调用百炼 API，system prompt 说明 launchd plist 格式 + 可用脚本
- AI 返回 plist XML 内容，直接写入 editingContent 供用户确认
- 也可以回答关于 launchd 配置的问题

### 修改文件

#### 3. `WorkspacePaths.swift`

```swift
static let launchdRoot = root.appendingPathComponent("launchd", isDirectory: true)
```

`ensureDirectories()` 中加入 `launchdRoot`。

#### 4. `TerminalTaskStore.swift`

- 保留进程发现能力（仍然有用于观察）
- 移除 `terminalInput`、`runTerminalInput()`、`canSendTerminalInput`
- 不再作为 Term 模块的主 store，降级为辅助

#### 5. `NotebookView.swift` — 重写 Term 模块 UI

**TerminalTopToolsView** 改造：
- ActiveFileBadge: 显示选中 plist 文件名
- ToolbarSearchField: 搜索所有 plist 配置文件（右上角）
- 按钮: refresh + 新建 plist

**TerminalTasksPane** 改造为 `LaunchdPane`：
```
┌─────────────────────────────────────┐
│  Plist 内容编辑器 (TextEditor)       │  ← 显示/编辑选中 plist
│  <?xml version="1.0"...>            │
│  <dict>                             │
│    <key>Label</key>                 │
│    ...                              │
├─────────────────────────────────────┤
│ [loaded jobs ▼] [AI输入...] [▶] [💾] │  ← 底部 toolbar
└─────────────────────────────────────┘
```

**底部 Toolbar**:
- 左侧: loaded job picker（显示已加载的 jobs，点击切换查看）
- 中间: AI 输入框（placeholder: "描述你要自动化的任务..."）
- 右侧: send 按钮 + save 按钮 + load/unload 按钮

#### 6. `NotchPanelController.swift`

- 新增 `launchdJobStore = LaunchdJobStore()`
- 新增 `launchdAIAgent = LaunchdAIAgent()`
- 传入 NotebookView

## 交互流程

```
用户在搜索框搜索 → 看到所有 plist 文件 → 点击选中 → 编辑器显示内容
用户点击左下角 loaded jobs picker → 看到运行中的 jobs → 点击 → 编辑器显示其 plist
用户在 AI 输入框输入 "每天早上9点跑 backup.sh" → AI 生成 plist → 写入编辑器
用户确认后点 save → 保存文件 → 可选点 load 加载到 launchd
```

## 实现步骤

1. `WorkspacePaths.swift` — 新增 `launchdRoot` 路径
2. `LaunchdJobStore.swift` — 新建，plist 管理 + launchctl 交互
3. `LaunchdAIAgent.swift` — 新建，AI 生成 plist
4. `TerminalTaskStore.swift` — 移除命令输入相关代码
5. `NotebookView.swift` — 重写 TerminalTopToolsView + TerminalTasksPane + toolbar
6. `NotchPanelController.swift` — 注入新 store
7. 构建 + rebuild dist
