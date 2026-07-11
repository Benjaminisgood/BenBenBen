# 历史优化推进记录（原 notchwow 阶段）

下面保留迁移前已经确认并提交的优化项，供 Git 历史追溯。当前产品身份是 BenBenBen；旧 `notchwow.*`、`notchNotes.*` 与 `com.notchwow.*` 仅作为迁移兼容契约存在。

## P0: 发布身份统一 ✅ 已完成

完成：

- 当时 SwiftPM 产品、target、源码目录和本地 bundle 统一为旧品牌 `notchwow`；现已再次统一为 `BenBenBen`。
- 当前 ZIP、bundle identifier 和仓库链接使用 `BenBenBen` / `io.github.benjaminisgood.benbenben`。
- 新偏好键使用 `benbenben.*`；`notchwow.*`、`notchNotes.*` 继续只读兼容。

## P0: API Key 迁移到 Keychain ✅ 已完成

完成：使用 Security.framework 封装 Keychain 存取，并做一次从旧 UserDefaults 到 Keychain 的迁移；迁移成功后删除旧值。

## P1: Terminal 进程检查器去留 ✅ 已完成

完成：删除 `TerminalTaskStore`、菜单触发入口和不可达的任务自动化代码；保留 Settings 中“在 Terminal 打开目录”的轻量辅助能力。任务编排统一由 Jobs 模块承担。

## P1: 可配置外部集成 ✅ 已完成

完成：Settings 增加 Benshell 根目录和 Conda 根目录字段；找不到时显示轻量提示，不影响 Markdown、AppleScript 和 Jobs 使用。Shell 命令发现、初始化环境、Conda 环境发现和 Jobs AI 上下文均跟随配置。

## P1: 统一删除语义 ✅ 已完成

完成：Markdown、Shell、Python、AppleScript 和 Jobs 均支持顶部垃圾桶按钮确认后移到废纸篓。Shell workspace 会一起移动 transcript、input 和 script。清空输出按钮统一移动到底部运行控制区。

## P1: launchd 服务兼容策略 ✅ 已更新

原 notchwow 阶段曾自动卸载缺少本地 plist 的 `com.notchwow.*` 服务。BenBenBen 迁移已经收紧该策略：新 Job 使用 `com.benbenben.*`；旧 `com.notchwow.*` 始终保持原状态，不自动重命名、卸载或删除。

## P2: 拆分 NotebookView ✅ 已完成

完成：`NotebookView.swift` 从 2921 行缩减为 365 行，功能视图按以下目录拆分：

```text
Views/Markdown/
Views/Shell/
Views/Python/
Views/AppleScript/
Views/Launchd/
Views/Shared/
```

## P2: 统一 AI transport 与脚本 AI 编辑 ✅ 已完成

完成：抽出共享 `BailianChatClient`，统一 endpoint、鉴权、超时和错误处理。Markdown 局部修改、Markdown 问答和 Launchd AI 保留各自 prompt。Shell、Python 和 AppleScript 底部输入区均可在直接运行与 AI 编辑之间切换；AI 会先展示完整脚本提案，再由用户拒绝或应用。

## P2: 文件错误可见化 ✅ 已完成

完成：`NoteStore`、`CodeFileStore`、`ShellWorkspaceStore` 增加统一 `lastError`，覆盖编辑保存、自动重命名、Shell 脚本写入和移到废纸篓失败。顶部工具栏显示可悬停查看详情的警告徽标。

## P2: 标准测试与 CI ✅ 已完成

完成：

1. 增加标准 SwiftPM test target；当前名称为 `BenBenBenTests`。
2. CI 执行 Debug build、Release build、标准测试、逻辑 smoke tests、Shell 语法检查和 ZIP 校验。
3. tag 发布流水线导入 Developer ID、执行 notarization、staple、ZIP 校验并上传 GitHub Release。

## 补充功能：自动化 Agent 指南 ✅ 已完成

完成：新增 `docs/AUTOMATION_AGENT_GUIDE.md`、可安装的 `docs/templates/keyoti-AGENTS.md` 和 `Scripts/install-keyoti-agent-guide.sh`。已把通用规则安装到 `~/keyoti/AGENTS.md`，并保留 `~/keyoti/shs/AGENTS.md` 的 Shell 专用说明。

## 小瑕疵 ✅ 已完成

- Markdown todo 根级条目回车后不再被额外缩进两格，与工具栏插入保持一致。
- Shell 输出为空时显示 `ready`、workspace 和 cwd。
