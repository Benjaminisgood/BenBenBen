# 开发与验证

## 1. 环境

```bash
swift --version
```

项目当前面向 macOS 14+ 和 Swift 6。产品和 target 均为 `notchwow`。

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
- `launchd` plist 模板转义与 Label 解析。
- 损坏 plist 的拒绝路径。

当前 Command Line Tools SDK 不包含 `XCTest` 或 Swift Testing 模块，所以本机使用独立 Swift runner。安装完整 Xcode 的环境还可以执行标准测试：

```bash
swift test
```

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
Sources/notchwow/            应用源码
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
- 修改 plist 或 Terminal 目录打开能力后检查 `dist/notchwow.app/Contents/Info.plist`：

```bash
plutil -lint dist/notchwow.app/Contents/Info.plist
```

- 修改脚本后执行：

```bash
bash -n Scripts/package-app.sh Scripts/notarize-app.sh Scripts/test-logic.sh script/build_and_run.sh
```

- 提交前执行：

```bash
git diff --check
git status --short
```

## 6. CI 与发布

`.github/workflows/ci.yml` 会在 macOS runner 上执行 Debug、Release、`swift test`、smoke tests、Shell 语法检查和 ZIP 校验。

`.github/workflows/release.yml` 会在 `v*` tag 上构建 Developer ID 签名版本、提交 notarization、staple app，并上传 `notchwow.zip`。需要配置：

```text
DEVELOPER_ID_APPLICATION_IDENTITY
DEVELOPER_ID_APPLICATION_P12_BASE64
DEVELOPER_ID_APPLICATION_P12_PASSWORD
BUILD_KEYCHAIN_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```
