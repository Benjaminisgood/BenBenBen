# BenBenBen 开发与验证

## 1. 环境

```bash
swift --version
codex --version
```

项目只支持 macOS 26+，当前以 Apple Silicon 和 Swift 6 为主要目标。SwiftPM product 与 target 均为 `BenBenBen`。

## 2. 常用命令

### Debug 构建

```bash
swift build --product BenBenBen
```

### 构建、启动和验证 app bundle

统一入口为：

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

脚本会构建 `BenBenBen`、重建并 ad-hoc 签名 `dist/BenBenBen.app`、打包 Runtime、停止旧 `BenBenBen` 进程并重新打开应用。

默认还会把 bundle 内 Runtime 原子安装到 `~/Library/Application Support/BenBenBen/Runtime/current`，并幂等更新 `~/.zshrc` 的受管区块。测试 App 而不修改机器 Runtime 时使用：

```bash
INSTALL_RUNTIME=0 UPDATE_ZSHRC=0 ./script/build_and_run.sh --verify
```

### 测试

```bash
swift test
./Scripts/test-logic.sh
./Scripts/test-runtime.sh
```

测试必须使用临时 workspace，并禁止真实 Git push、真实端口清理和真实 `launchd` bootstrap/bootout。

`test-runtime.sh` 覆盖 Runtime manifest、原子安装、重复迁移、`~/.zshrc` 备份、CLI JSON 输出和非只读 action 审批。

### Release 构建

```bash
swift build -c release --product BenBenBen
```

### Release app bundle

```bash
./Scripts/package-app.sh
```

脚本生成 `dist/BenBenBen.app`、验证签名，并默认复制到 `/Applications/BenBenBen.app`。Bundle ID 是 `io.github.benjaminisgood.benbenben`；默认 `SIGN_IDENTITY=-`，用于本机 ad-hoc 签名。

只验证打包而不覆盖 `/Applications`：

```bash
APP_DIR=/tmp/BenBenBen.app COPY_TO_APPLICATIONS=0 ./Scripts/package-app.sh
```

## 3. 目录结构

```text
Sources/BenBenBen/
├── App/                    SwiftUI App、AppModel、工作台环境
├── Agent/                  Codex app-server runtime 与 UI store
├── Personal/               WorkspaceRegistry、FTS5 索引、个人任务
└── Views/                  主窗口和既有工作台视图
Runtime/                    版本化 Benshell、CLI、manifest、安装器
Vendor/swift-markdown-engine/
Resources/                  图标和 App 资源
Scripts/                    打包、Runtime 和测试脚本
Tests/BenBenBenTests/       SwiftPM tests
Tests/LogicSmokeTests/      独立逻辑 smoke tests
Sources/BenBenBenLoginHelper/ 登录时仅启动伙伴的嵌套 helper
ProtocolSchemas/            按 Codex 版本提交的 app-server schema
docs/                       静态主页和项目文档
dist/                       未跟踪的本地 app bundle
```

## 4. 生成产物

以下内容不应提交：

```text
.build/
build/
dist/*.app/
.understand-anything/intermediate/
.understand-anything/tmp/
```

GitHub Actions 和 Release workflow 生成 `BenBenBen.app` / `BenBenBen.zip` artifact。仓库不再跟踪本地 app bundle 二进制。

## 5. 修改后的最小验证

- Swift/SwiftUI：`swift build --product BenBenBen`，再运行相关 `swift test`。
- Runtime/CLI：`./Scripts/test-runtime.sh`。
- App 生命周期、窗口或刘海 panel：`INSTALL_RUNTIME=0 UPDATE_ZSHRC=0 ./script/build_and_run.sh --verify`。
- bundle plist：

```bash
plutil -lint dist/BenBenBen.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 dist/BenBenBen.app
```

- Shell：

```bash
bash -n \
  script/build_and_run.sh \
  Scripts/build_and_run.sh \
  Scripts/copy-runtime.sh \
  Scripts/embed-login-helper.sh \
  Scripts/install-keyoti-agent-guide.sh \
  Scripts/install-runtime.sh \
  Scripts/package-app.sh \
  Scripts/notarize-app.sh \
  Scripts/test-logic.sh \
  Scripts/test-runtime.sh
zsh -n Runtime/install.zsh
python -m py_compile \
  Runtime/bin/benbenben \
  Runtime/bin/benbenben-mcp \
  Scripts/process-mascot-assets.py
```

- 提交前：

```bash
git diff --check
git status --short
```

## 6. Codex 协议契约

Agent 首版只连接外部 `codex app-server --stdio`。不要读取或复制 Codex `auth.json`，不要自动升级用户选择的 Codex executable，也不要默认启用实验协议。

升级已验证 Codex 版本时：

1. 从该 executable 生成协议 schema。
2. 提交 schema 与已验证版本信息。
3. 运行初始化、登录状态、线程恢复、delta、Diff、审批/拒绝、interrupt、崩溃重启和未知事件契约测试。
4. 确认宽松解码可以记录新增字段或事件。

当前 schema 基线由 `/opt/homebrew/bin/codex app-server generate-json-schema --out ProtocolSchemas/Codex-<version>` 生成。生成目录会包含实验定义，但客户端仍必须发送 `experimentalApi: false`，不能因 schema 中出现定义就调用实验接口。

## 7. CI 与发布

`.github/workflows/ci.yml` 在 macOS 26 runner 上执行 Debug/Release build、SwiftPM tests、logic/runtime tests、Shell 语法和 ZIP 校验。

`.github/workflows/release.yml` 在 `v*` tag 上构建 Developer ID 签名版本、notarize、staple，并上传 `BenBenBen.zip`。需要：

```text
DEVELOPER_ID_APPLICATION_IDENTITY
DEVELOPER_ID_APPLICATION_P12_BASE64
DEVELOPER_ID_APPLICATION_P12_PASSWORD
BUILD_KEYCHAIN_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```

本地个人版本默认 ad-hoc 签名；未配置 Developer ID 时，notarization 不阻断本地验收。

## 8. 迁移注意事项

- 不要机械删除 `notchwow.*`、`notchNotes.*`、旧 Keychain service 或 `com.notchwow.*`；它们是明确保留的迁移兼容契约。
- 新偏好键、bundle 与 Jobs 分别使用 `benbenben.*`、`io.github.benjaminisgood.benbenben`、`com.benbenben.*`。
- 旧 `com.notchwow.*` Jobs 必须保持当前状态，不得自动重命名、卸载或删除。
