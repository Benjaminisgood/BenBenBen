# 开发与验证

## 1. 环境

```bash
swift --version
```

项目当前面向 macOS 14+ 和 Swift 6。主产品是 `notchwow`，不是旧名称 `NotchNotes`。

## 2. 常用命令

### 调试构建

```bash
swift build
```

### 运行和验证 app bundle

```bash
./script/build_and_run.sh run
./script/build_and_run.sh verify
./script/build_and_run.sh logs
./script/build_and_run.sh telemetry
```

脚本会构建 `notchwow`、重建 `dist/notchwow.app`、停止旧进程并重新打开应用。

### 修改源码后的最小人工流程

```bash
swift build
cp -f .build/debug/notchwow dist/notchwow.app/Contents/MacOS/notchwow
pkill -x notchwow || true
sleep 0.3
open dist/notchwow.app
```

### 逻辑 smoke tests

```bash
./Scripts/test-logic.sh
```

当前 smoke tests 覆盖：

- 默认路径是否基于当前用户 Home。
- 文件名清理规则。
- 同名文件后缀生成。
- Terminal 摘要中的 Home 缩写。
- `launchd` plist 模板转义与 Label 解析。
- 损坏 plist 的拒绝路径。

当前 Command Line Tools SDK 不包含 `XCTest` 或 Swift Testing 模块，所以仓库使用独立 Swift runner。未来接入完整 Xcode 工具链后，可以再补标准 SwiftPM test target。

### Release 构建

```bash
swift build -c release --product notchwow
```

### Release app bundle

```bash
./Scripts/package-app.sh
```

该脚本会生成 `dist/notchwow.app`、执行签名校验，并复制到 `/Applications/notchwow.app`。默认 `SIGN_IDENTITY=-`，仅适合本机测试。

如需只验证打包而不覆盖 `/Applications`：

```bash
APP_DIR=/tmp/notchwow.app COPY_TO_APPLICATIONS=0 ./Scripts/package-app.sh
```

## 3. 目录结构

```text
Sources/NotchNotes/          应用源码
Vendor/swift-markdown-engine 内置 Markdown 编辑器
Resources/                   图标资源
Scripts/                     打包和逻辑验证脚本
script/                      本地调试运行脚本
Tests/LogicSmokeTests/       独立逻辑测试入口
docs/                        静态页和项目文档
dist/                        本地 app bundle
```

## 4. 生成产物

以下目录不应提交新的生成内容：

```text
.build/
build/
dist/
.understand-anything/intermediate/
.understand-anything/tmp/
```

注意：仓库历史中已经跟踪了 `dist/notchwow.app`，因此构建后 Git 仍会显示二进制变化。是否彻底移除跟踪中的 app bundle，需要单独决定发布策略。

## 5. 修改建议

- 修改 UI 后至少执行一次 `./script/build_and_run.sh verify`。
- 修改 plist 或 Terminal 自动化后检查 `dist/notchwow.app/Contents/Info.plist`：

```bash
plutil -lint dist/notchwow.app/Contents/Info.plist
```

- 修改脚本后执行：

```bash
bash -n Scripts/package-app.sh Scripts/test-logic.sh script/build_and_run.sh
```

- 提交前执行：

```bash
git diff --check
git status --short
```
