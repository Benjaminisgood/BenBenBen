# 项目审查报告

## 1. 审查范围

本次检查覆盖：

- `Sources/notchwow` 全部 Swift 源码。
- `Vendor/swift-markdown-engine` 的结构、编译结果和 warning。
- SwiftPM manifest、调试运行脚本、Release 打包脚本。
- README、静态主页和 `.understand-anything` 生成缓存。
- Debug build、Release build、逻辑 smoke tests、Shell 语法、plist 校验和应用重启。

## 2. 已自动修复

### 可移植性

- 把 `/Users/ben/keyoti`、`/Users/ben/Desktop/Benshell`、`/Users/ben/miniforge3` 改为基于当前用户 Home 的动态路径。
- Terminal 命令摘要不再写死 `/Users/ben`。
- `LaunchdAIAgent` 生成提示词中的 Python 路径改为动态路径。

### UI

- 设置弹窗窗口尺寸由 `400x408` 修正为与内容一致的 `440x480`，避免裁切。
- 第五个工作台模式从误导性的 `Term` 改名为 `Jobs`。
- 菜单项从 `Show Terminal Tasks` 改为 `Show Launchd Jobs`。
- 未公开的 Terminal 进程检查器改为 lazy 初始化，不再在每次启动时无意义地每 3 秒扫描进程。

### Launchd

- plist 模板改用 `PropertyListSerialization` 生成，正确处理 XML 转义。
- plist Label 改用系统 Property List 解析，不再手工截取 XML 字符串。

### 构建与仓库卫生

- `Scripts/package-app.sh` 更新到当前产品名 `notchwow`，只复制当前 SwiftPM 产物。
- Release bundle 增加 Apple Events 用途说明。
- 清理被提交的 `.understand-anything/intermediate` 和 `tmp` 缓存。
- 为上述缓存增加 Git ignore 规则。
- 删除 `NotebookView.swift` 中无引用的旧 UI、无引用的标签删除路径和未使用的 `lsof` helper。
- 清理 vendored MarkdownEngine 中两处始终成功的冗余类型转换。

## 3. 验证结果

已通过：

```bash
swift build
./Scripts/test-logic.sh
swift build -c release --product notchwow
bash -n Scripts/package-app.sh Scripts/test-logic.sh script/build_and_run.sh
git diff --check
plutil -lint dist/notchwow.app/Contents/Info.plist
```

并已复制 Debug 二进制、重启 `dist/notchwow.app`、确认 `notchwow` 进程存活。

## 4. 仍需决定

以下项目需要产品取舍，没有自动修改：

- `docs/index.html` 的品牌和下载链接仍需统一到当前仓库。
- `dist/notchwow.app` 仍在 Git 历史中被跟踪，和 `.gitignore` 目标不一致。
- Terminal 进程检查器代码仍保留，但没有可见工作台入口。
- 百炼 API Key 仍明文保存在 `UserDefaults`。
- `NotebookView.swift` 仍然较大，适合按模式拆分。
- 多处磁盘写入使用 `try?`，错误不会显示给用户。
- AI 请求实现有三套相似客户端，可抽出共享 transport。
- `LaunchdJobStore.cleanupOrphanedServices` 的自动清理策略需要确认是否符合预期。

具体建议和推荐顺序见 `OPTIMIZATION_PROPOSALS.md`。
