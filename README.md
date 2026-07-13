# BenBenBen

![BenBenBen preview](docs/assets/readme-hero.png)

`BenBenBen` 是住在 MacBook 刘海后面的个人 Codex 伙伴。紧凑刘海悬停后只向下展开成小型黑色正方形，Ben龙保持原位；点击龙开始或暂停语音。HTML、PY、MD、SCRIPTS、PLIST 五个多标签共同窗口，加上单实例任务窗口，共同组成六窗口协作界面。

## 核心能力

- 通过 `codex app-server --stdio` 管理登录、线程、流式事件、图像、审批和中断。
- 语音是唯一任务输入：口头指定新任务、继续当前任务、打开窗口/标签页，以及开始或停止屏幕共享。
- 五类文件共同窗口支持多标签；每次语音会把所有可见窗口的全部标签页自动作为 agent 背景信息。
- 任务窗口左侧显示历史任务、右侧显示计划/活动/回复/审批，一次只选择并继续一个聊天。
- 文件窗口直接读写永久内容目录下的 `html`、`mds`、`pys`、`shs/workspace-scripts`、`applescripts` 和 `launchds`；默认目录为 `~/keyoti`，可在设置中修改。
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

设置页可将整个内容根目录永久切换到其他位置，并统一配置任务权限、语音/屏幕授权和 Ben龙活跃程度。

## 文档

- [架构说明](docs/ARCHITECTURE.md)
- [开发与验证](docs/DEVELOPMENT.md)
- [自动化 Agent 指南](docs/AUTOMATION_AGENT_GUIDE.md)

## 发布

- [BenBenBen Releases](https://github.com/Benjaminisgood/BenBenBen/releases/latest)
- [BenBenBen Homepage](docs/index.html)
