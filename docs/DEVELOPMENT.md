# BenBenBen 开发与验证

## SwiftPM 产品

- `BenBenBen`：macOS GUI 应用可执行文件。
- `BenBenBenLoginHelper`：登录项 helper。
- `BenBenBenTests`：当前产品逻辑和 Codex 协议测试。

## 目录

```text
Sources/BenBenBen/
├── Agent/                 Codex 协议、进程和状态
├── App/                   App 入口、模型与登录项
├── Mascot/                龙状态、图像和语音
├── Runtime/               manifest 读取
└── Views/Main/            刘海、设置、菜单、任务和共同窗口
Runtime/                    CLI、MCP helper、shell 环境
ProtocolSchemas/            当前 Codex schema 快照
Resources/Mascot/           App 使用的龙图片
Scripts/                    构建、打包、Runtime 和测试脚本
Scripts/benshell/           合并后的 Shell 命令、bootstrap 与 zsh 配置
```

## 日常验证

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/test-runtime.sh
INSTALL_RUNTIME=0 UPDATE_ZSHRC=0 ./Scripts/build_and_run.sh --verify
```

`swift test` 是唯一 Swift 逻辑测试入口。UI 验证使用打包后的 App，不用裸 `swift run` 替代。

## 协议基线

```bash
/opt/homebrew/bin/codex app-server generate-json-schema \
  --out ProtocolSchemas/Codex-<version>
```

客户端只使用当前 thread/turn/item 接口。协议升级后先更新快照，再运行完整测试。

## Runtime 规则

- 修改 Runtime 时同步更新 `Runtime/VERSION` 和 `manifest.json`。
- `benbenben` 是完整 CLI；`bbb` 是短别名。
- Runtime 启动不得隐式执行 Git 同步、Brewfile、defaults、launchctl 或端口清理。
- 测试必须使用临时 HOME，不得接触真实服务。

## launchd

新 Job 只使用 `com.benbenben.*`。不要自动操作其他前缀；尤其不得自动改名、卸载或删除现有 `com.notchwow.*` Job。
