# 待讨论优化建议

下面这些优化需要确认产品方向。每完成一项就及时git

## P0: 发布身份统一 ✅ 已完成

完成：

- SwiftPM 产品、target、源码目录和本地 bundle 均统一为 `notchwow`。
- `docs/index.html`、ZIP、bundle identifier 和仓库链接均切换到当前项目。
- 默认偏好键切换到 `notchwow.*`，并保留一次旧键迁移。

## P0: API Key 迁移到 Keychain ✅ 已完成

完成：使用 Security.framework 封装 Keychain 存取，并做一次从旧 UserDefaults 到 Keychain 的迁移；迁移成功后删除旧值。

## P1: Terminal 进程检查器去留

现状：`TerminalTaskStore` 可以发现进程组、聚焦 Terminal tab、读取快照、结束任务，但当前没有可见 UI。只有菜单中的“新建 Terminal 窗口”和“刷新 Terminal Tasks”仍会触发它。

不再需要Terminal模块，完全迁移成jobs这个最终方案

## P1: 可配置外部集成

现状：`~/Desktop/Benshell` 和 `~/miniforge3` 已经改为动态 Home，但仍是固定约定。

推荐：在 Settings 增加 Benshell 根目录和 Conda 根目录字段；找不到时显示轻量提示，不影响 Markdown、AppleScript 和 Jobs 使用。

这些集成确实是个人固定环境，不过让其他用户能够配置也很不错，可以有。

## P1: 笔记删除语义

现状：Markdown 文件会自动发现并同步。旧代码里曾存在“Remove current tab”，但没有明确是关闭视图还是删除磁盘文件；本次已移除这条未使用路径。

恢复删除功能，使用“Move to Trash”并弹一次确认，而不是静默删除文件。单纯“关闭 tab”需要额外维护隐藏列表。提供删除、移到废纸篓，还是不提供删除。

并且所有的模块都支持删除到废纸篓，并且UI上统一使用当前垃圾桶标识的位置按钮，至于当前的清空output等改到下面运行、暂停的按钮旁边，模块UI尽量统一。

## P1: 自动清理 launchd 服务

现状：启动时会卸载所有缺少本地 plist 的 `com.notchwow.*` 服务。

推荐：改成先列出 orphan，再由用户点击清理；避免用户移动文件后服务被自动卸载。

保留自动清理即可

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

## P2: 统一 AI transport

现状：Markdown 局部修改、Markdown 问答、Launchd AI 各自实现 URLRequest、鉴权和错误处理。

推荐：抽出共享 `BailianChatClient`，保留各功能自己的 prompt 和响应解析。

收益：减少重复、统一错误提示、便于未来配置 endpoint 和超时。

当前applescript缺少ai实现的功能，把这个也要加上。

## P2: 文件错误可见化

现状：多个 Store 使用 `try?` 创建目录或写文件，失败时用户看不到原因。

推荐：先给 `NoteStore`、`CodeFileStore`、`ShellWorkspaceStore` 增加统一的 `lastError`，在工具栏展示；再逐步覆盖附件和 transcript。

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
