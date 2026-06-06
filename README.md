# notchwow

![notchwow preview](docs/assets/readme-hero.png)

`notchwow` 是一个常驻 MacBook 刘海区域的原生 macOS 工作台。鼠标移到屏幕顶部中央后，紧凑面板会展开为一个深色工具抽屉，用于快速记录 Markdown、维护 Scripts、运行 Python，以及管理 `launchd` 任务。

当前仓库已经扩展为面向本机自动化的个人工作台，并统一使用 `notchwow` 品牌。

## 功能

- Markdown 笔记：实时渲染、搜索、`[[笔记标题]]` 跳转、附件粘贴、LaTeX、代码块高亮、AI 局部修改与问答。
- Scripts 工作区：合并 Shell 与 AppleScript 文件维护，按 toolkit 查找命令，并在 Terminal.app 中启动。
- Python 工作区：脚本编辑、Conda 环境发现、持久 REPL、脚本执行、AI 脚本提案。
- Jobs 工作区：创建、编辑、加载、卸载 `launchd` plist，并可用 AI 生成任务配置。
- 编辑器辅助：Scripts 和 Python 底部工具栏可直接在 VS Code 中打开当前文件。
- Terminal 辅助：可从 Settings 中把工作目录直接在 Terminal 打开；Scripts 命令由原生 Terminal 执行。
- 统一删除：各工作区顶部垃圾桶按钮会在确认后把当前资源移到废纸篓。

## 环境要求

- macOS 14 或更高版本。
- Swift 6 工具链。
- 可选：`~/miniforge3`，用于 Conda 环境发现和 Python REPL，可在 Settings 中覆盖。
- 内置：`Scripts/benshell`，用于加载原 Benshell 初始化脚本和命令目录；仍可在 Settings 中覆盖根目录。

## 快速开始

```bash
swift build
./Scripts/build_and_run.sh verify
```

也可以直接运行 SwiftPM 产品：

```bash
swift run notchwow
```

展开应用后，在设置中可以修改 Markdown、Shell、Python、AppleScript 和 `launchd` 的工作目录，也可以覆盖 Benshell 与 Conda 根目录。

## 测试

当前 Command Line Tools SDK 不带 `XCTest` 或 Swift Testing 模块，因此仓库提供可直接运行的逻辑 smoke tests：

```bash
./Scripts/test-logic.sh
```

安装完整 Xcode 后还可以执行标准 SwiftPM tests：

```bash
swift test
```

## 打包

调试运行：

```bash
./Scripts/build_and_run.sh run
```

Release 打包并复制到 `/Applications/notchwow.app`：

```bash
./Scripts/package-app.sh
```

公开分发前仍需要 Developer ID 签名和 notarization。

## 默认数据目录

应用默认把用户数据保存在 `~/keyoti`：

```text
~/keyoti/
├── mds/
├── pys/
├── shs/
├── applescripts/
└── launchds/
```

原 `/Users/ben/Desktop/Benshell/scripts` 已迁入仓库内 `Scripts/benshell/scripts`。Scripts 模块不再把 zsh alias 当作命令来源，命令发现来自可执行脚本的 `Commands:` / `Controller commands:` 说明块，以及本地 Shell/AppleScript 文件。

## 项目文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发与验证](docs/DEVELOPMENT.md)
- [notchwow Markdown 语法（AI Agent 版）](docs/NOTCHWOW_MARKDOWN_SYNTAX_FOR_AGENTS.md)
- [自动化 Agent 指南](docs/AUTOMATION_AGENT_GUIDE.md)
- [Benshell 迁移说明](docs/BENSHELL_MIGRATION.md)
- [代码审查报告](docs/AUDIT_REPORT.md)
- [待讨论优化建议](docs/OPTIMIZATION_PROPOSALS.md)

## 发布页

项目主页和最新发布：

- [notchwow Releases](https://github.com/Benjaminisgood/Notchwow/releases/latest)
- [notchwow Homepage](docs/index.html)
