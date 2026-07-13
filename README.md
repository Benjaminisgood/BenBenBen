# BenBenBen

![BenBenBen preview](docs/assets/readme-hero.png)

`BenBenBen` 是住在 MacBook 刘海后面的个人 Codex 伙伴。主界面只保留龙刘海、对话、语音、屏幕上下文、任务进度和审批；HTML、PY、MD、SCRIPTS、PLIST 五个共同窗口直接观察 `~/keyoti` 中的最新文件。

## 核心能力

- 通过 `codex app-server --stdio` 管理登录、线程、流式事件、图像、审批和中断。
- 支持并行任务、运行中引导、语音对话和显式屏幕上下文。
- 五类共同窗口直接读写 `~/keyoti/html`、`mds`、`pys`、`shs/workspace-scripts`、`applescripts` 和 `launchds`。
- App 内置版本化 Runtime；`benbenben` 是唯一完整 CLI，`bbb` 是当前短别名。
- 登录项 helper 只启动同一个刘海伙伴。

## 安全默认值

- 读取和搜索可直接执行，写入和执行按风险走 Codex 审批。
- Runtime action 只能引用 `Runtime/manifest.json` 中的固定 action ID、可执行文件和参数。
- 新 launchd Job 只使用 `com.benbenben.*`。应用不迁移或管理其他前缀；按仓库约定，不自动改名、卸载或删除现有 `com.notchwow.*` Job。

## 环境要求

- macOS 26 或更高版本
- Apple Silicon
- Swift 6
- 已安装并登录的 Codex CLI

## 构建与运行

```bash
swift build --product BenBenBen
INSTALL_RUNTIME=0 UPDATE_ZSHRC=0 ./Scripts/build_and_run.sh --verify
```

这是 SwiftPM GUI 应用；UI 验收应通过生成的 `.app` bundle 启动。

## Runtime

```bash
benbenben runtime status --json
benbenben tools list --json
benbenben tools status --json
benbenben tools run runtime.version --json
```

非只读 action 必须显式加 `--yes`。Runtime 安装器不会自动运行 Brewfile、macOS defaults、Git 同步、服务启动或端口清理。

## 测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/test-runtime.sh
```

## 打包

```bash
./Scripts/package-app.sh
```

Bundle ID 为 `io.github.benjaminisgood.benbenben`。本地 `dist/*.app` 不进入 Git。

## 默认数据目录

```text
~/keyoti/
├── html/
├── mds/
├── pys/
├── shs/workspace-scripts/
├── applescripts/
└── launchds/
```

## 文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发与验证](docs/DEVELOPMENT.md)
- [自动化 Agent 指南](docs/AUTOMATION_AGENT_GUIDE.md)

## 发布

- [BenBenBen Releases](https://github.com/Benjaminisgood/BenBenBen/releases/latest)
- [BenBenBen Homepage](docs/index.html)
