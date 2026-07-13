# BenBenBen

![BenBenBen preview](docs/assets/readme-hero.png)

`BenBenBen` 是住在 MacBook 刘海后面的个人 Codex 伙伴。紧凑态只露出“Ben龙”的一部分；单击后它走近并聚焦当前对话，双击则直接进入新任务输入状态。用户也可直接语音或文字对话。HTML、PY、MD、SCRIPTS、PLIST 五个持久共同窗口可从菜单栏按需打开。

原始资料始终保存在 `~/keyoti`。App 的 SQLite 数据库只保存可重建的搜索索引和 UI 元数据，不替代 Markdown、脚本、Python、AppleScript 或 plist 文件。

## 核心能力

- 龙即主界面：刘海 `NSPanel` 只有藏身态和近身对话态；旧的写死功能按钮不再占据展开面板。
- 五类共同窗口：HTML / Python / Markdown / Shell 与 AppleScript / launchd plist 都直接观察 `~/keyoti` 文件；Codex 或用户改动后自动刷新，每次 composer 提交都会创建一个可并行运行的独立任务。
- Codex 主智能：通过外部 `codex app-server --stdio` 管理 ChatGPT 登录、线程、流式事件、图像输入、Diff、审批和中断；不复制 Codex 的 `auth.json`。
- 可见屏幕上下文：用户显式打开后，每三秒采样屏幕；显著变化时最多每十五秒把当前画面作为 `localImage` 交给 Codex 反应，可随时停止。
- 个人知识与任务：索引 `~/keyoti` 中的 Markdown、Shell、Python、AppleScript 和 Jobs；识别 Markdown checkbox、`TODO:`、`待完成:`、日期与生活/学习/工作标签。
- 兼容底座：原有 MarkdownEngine、文件锁、Conda/Python、Terminal 和 `launchd` 适配器继续保留，百炼 API 只作为旧版备选。
- Ben龙刘海伙伴：业务状态和唤醒态优先；只有藏在刘海后且没有任务时，才会拍照、散步、喝茶、发呆、休息、阅读、听歌、浇花等自己玩，无刘海屏幕回退为顶部浮动入口。
- 统一 Runtime：App 内置完整 Benshell，并原子安装到 `~/Library/Application Support/BenBenBen/Runtime/current`。Terminal 与 App 使用同一份 manifest 和命令目录。
- 稳定 MCP helper：`benbenben-mcp` 提供个人资料搜索、文档读取、近期活动、固定 workflows 与 Jobs 状态；写入和执行动作回到原生审批。

## 安全默认值

- 读取和搜索可直接执行。
- 文件修改先展示 Diff。
- 命令、Jobs、删除、Git push 和外发动作必须确认。
- Runtime action 只能引用 `Runtime/manifest.json` 中的固定 action ID、executable 与 argv，不能拼接任意 shell。
- 新建 Jobs 使用 `com.benbenben.*`。既有 `com.notchwow.*` 仅作为迁移兼容项识别，绝不自动重命名、卸载或删除。

## 环境要求

- macOS 26 或更高版本。
- Apple Silicon 为当前主要目标。
- Swift 6 工具链。
- 已安装并登录的 Codex CLI；默认自动探测当前 `codex` executable，也可在 Settings 中选择。
- 可选：`~/miniforge3`，用于 Conda 环境发现和 Python REPL。

## 快速开始

```bash
swift build --product BenBenBen
./script/build_and_run.sh --verify
```

这是 SwiftPM GUI 应用；UI 验收应通过 `.app` bundle 启动，不使用裸 `swift run` 进程替代。

`build_and_run.sh` 会构建并 ad-hoc 签名 `dist/BenBenBen.app`、打包 Runtime、启动 App，并在默认情况下幂等安装 Runtime。若只想验证 App 而不改动 Runtime 或 `~/.zshrc`：

```bash
INSTALL_RUNTIME=0 UPDATE_ZSHRC=0 ./script/build_and_run.sh --verify
```

## Runtime 与 CLI

安装后的主命令是 `benbenben`，短别名为 `bbb`：

```bash
benbenben runtime status --json
benbenben tools list --json
benbenben tools status --json
benbenben tools run runtime.version --json
```

非只读 action 必须显式加 `--yes`。旧 `benshell`、`notchwow` 和 `nw` 入口保留为兼容转发器。

Runtime 安装器不会自动运行 Brewfile、macOS defaults、Git sync/push、服务启动或端口清理。

“登录时启动”默认关闭。启用后由签名在主 bundle 内的 Login Item helper 启动同一个刘海伙伴，不弹出其他工作台窗口。

## 测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/test-logic.sh
./Scripts/test-runtime.sh
```

测试应使用临时 workspace，不得操作真实 push、真实端口或真实 `launchd` 服务。

## 打包

本机 ad-hoc 打包并复制到 `/Applications/BenBenBen.app`：

```bash
./Scripts/package-app.sh
```

Bundle ID 为 `io.github.benjaminisgood.benbenben`。未配置 Developer ID 时，notarization 不作为本地版本的阻断条件。仓库不跟踪 `dist/*.app`；CI 与 GitHub Release 负责生成发布 artifact。

## 默认数据目录

```text
~/keyoti/
├── html/
├── mds/
│   └── Inbox.md
├── pys/
├── shs/
│   └── workspace-scripts/
├── applescripts/
└── launchds/
```

BenBenBen 不会自动搬迁或删除这些个人资料。

## 迁移兼容

- 当前仓库由原 notchwow checkout 原地迁移并保留 Git 历史。
- `notchwow.*`、`notchNotes.*`、旧 Keychain service 和旧目录设置继续只读兼容，再迁移到 `benbenben.*`。
- 新 Jobs 使用 `com.benbenben.*`；旧 `com.notchwow.*` 保持原状态。
- `/Users/ben/Desktop/Benshell` 与旧 App bundle 在验收完成前保留为迁移备份。

## 项目文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发与验证](docs/DEVELOPMENT.md)
- [BenBenBen Markdown 语法（AI Agent 版）](docs/NOTCHWOW_MARKDOWN_SYNTAX_FOR_AGENTS.md)
- [自动化 Agent 指南](docs/AUTOMATION_AGENT_GUIDE.md)
- [Benshell / Runtime 迁移说明](docs/BENSHELL_MIGRATION.md)
- [历史代码审查报告](docs/AUDIT_REPORT.md)
- [历史优化推进记录](docs/OPTIMIZATION_PROPOSALS.md)

Codex 富客户端协议说明见 [Codex app-server](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)。

## 发布页

- [BenBenBen Releases](https://github.com/Benjaminisgood/BenBenBen/releases/latest)
- [BenBenBen Homepage](docs/index.html)
