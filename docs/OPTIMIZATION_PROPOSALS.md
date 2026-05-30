# 待讨论优化建议

下面这些优化需要确认产品方向。每完成一项就及时git

## P0: 发布身份统一 ✅ 已完成

完成：

- SwiftPM 产品、target、源码目录和本地 bundle 均统一为 `notchwow`。
- `docs/index.html`、ZIP、bundle identifier 和仓库链接均切换到当前项目。
- 默认偏好键切换到 `notchwow.*`，并保留一次旧键迁移。

## P0: API Key 迁移到 Keychain ✅ 已完成

完成：使用 Security.framework 封装 Keychain 存取，并做一次从旧 UserDefaults 到 Keychain 的迁移；迁移成功后删除旧值。

## P1: Terminal 进程检查器去留 ✅ 已完成

完成：删除 `TerminalTaskStore`、菜单触发入口和不可达的任务自动化代码；保留 Settings 中“在 Terminal 打开目录”的轻量辅助能力。任务编排统一由 Jobs 模块承担。

## P1: 可配置外部集成 ✅ 已完成

现状：`~/Desktop/Benshell` 和 `~/miniforge3` 已经改为动态 Home，但仍是固定约定。

推荐：在 Settings 增加 Benshell 根目录和 Conda 根目录字段；找不到时显示轻量提示，不影响 Markdown、AppleScript 和 Jobs 使用。

这些集成确实是个人固定环境，不过让其他用户能够配置也很不错，可以有。

## P1: 笔记删除语义 ✅ 已完成

现状：Markdown 文件会自动发现并同步。旧代码里曾存在“Remove current tab”，但没有明确是关闭视图还是删除磁盘文件；本次已移除这条未使用路径。

恢复删除功能，使用“Move to Trash”并弹一次确认，而不是静默删除文件。单纯“关闭 tab”需要额外维护隐藏列表。提供删除、移到废纸篓，还是不提供删除。

并且所有的模块都支持删除到废纸篓，并且UI上统一使用当前垃圾桶标识的位置按钮，至于当前的清空output等改到下面运行、暂停的按钮旁边，模块UI尽量统一。

## P1: 自动清理 launchd 服务 ✅ 已完成

完成：按产品决定保留启动时自动卸载缺少本地 plist 的 `com.notchwow.*` 服务。

## P2: 拆分 NotebookView

现状：清理后 `NotebookView.swift` 仍承载多个模式和通用 UI。

推荐按功能拆成：

```text
Views/Markdown/
Views/Shell/
Views/Python/
Views/AppleScript/
Views/Launchd/
Views/Shared/
```

结构优化

## P2: 统一 AI transport 与脚本 AI 编辑 ✅ 已完成

完成：抽出共享 `BailianChatClient`，统一 endpoint、鉴权、超时和错误处理。Markdown 局部修改、Markdown 问答和 Launchd AI 保留各自 prompt。Shell、Python 和 AppleScript 底部输入区均可在直接运行与 AI 编辑之间切换；AI 会先展示完整脚本提案，再由用户拒绝或应用。

## P2: 文件错误可见化 ✅ 已完成

完成：`NoteStore`、`CodeFileStore`、`ShellWorkspaceStore` 增加统一 `lastError`，覆盖编辑保存、自动重命名、Shell 脚本写入和移到废纸篓失败。顶部工具栏显示可悬停查看详情的警告徽标。

## P2: 标准测试与 CI

现状：当前 Command Line Tools SDK 没有 `XCTest` 或 Swift Testing 模块，仓库使用独立 smoke tests。

## 补充功能
当前我会让别的agents为我生成shell、py和as脚本，并且通过jobs模块的plist进行编排，shell、py和as脚本之间也会互相调用，这些脚本都存储在/Users/ben/keyoti 路径下，我该如何让agent知道如何了解这个项目，并指导如何正确的写脚本进正确的位置，并高质量的编排和自动化。

## 小瑕疵：
当前md模块的todolist回车后会出现和直接点击按钮构建的缩进不一的问题

推荐：

1. 在安装完整 Xcode 的 CI runner 上增加标准 SwiftPM tests。
2. CI 执行 Debug build、Release build、逻辑测试、Shell 语法检查。
3. 发布流水线增加 Developer ID 签名、notarization 和 ZIP 校验。
