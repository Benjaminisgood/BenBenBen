# Benshell / Runtime 迁移说明

## 结果

完整 Benshell 现在作为版本化 Runtime 随 BenBenBen 打包：

```text
Runtime/
├── VERSION
├── manifest.json
├── install.zsh
├── bin/
│   ├── benbenben
│   ├── bbb
│   ├── benshell
│   ├── notchwow
│   └── nw
└── Benshell/
    ├── Brewfile
    ├── bootstrap/
    ├── scripts/
    └── zsh/
```

`Scripts/copy-runtime.sh` 把它复制到 `BenBenBen.app/Contents/Resources/Runtime`。安装器再以版本目录加原子符号链接的方式安装到：

```text
~/Library/Application Support/BenBenBen/Runtime/
├── releases/<version>/
└── current -> releases/<version>
```

`/Users/ben/Desktop/Benshell` 不会自动删除，旧仓库和远端继续作为迁移备份。

## 安装与 shell 迁移

App 本地构建默认调用 bundle 内 `Runtime/install.zsh`。也可以独立运行：

```bash
./Scripts/install-runtime.sh doctor
./Scripts/install-runtime.sh install
./Scripts/install-runtime.sh status
```

安装器会：

1. 校验 `VERSION`、`manifest.json`、CLI 和 Benshell init。
2. 将新版本复制到 `Runtime/releases/<version>`。
3. 原子切换 `Runtime/current`。
4. 备份 `~/.zshrc`，幂等维护单个 `BenBenBen Runtime` 区块。
5. 让 Terminal 与 App 共用相同 `BENBENBEN_RUNTIME_HOME`、`BENSHELL_HOME` 和 PATH。

安装器不会运行 Brewfile、macOS defaults、Git sync/push、服务启动或端口清理。使用 `--no-zshrc` 可只安装 Runtime，不改 shell 配置。

## 统一 CLI

主入口是 `benbenben`，短入口是 `bbb`：

```bash
benbenben version
benbenben runtime status --json
benbenben tools list --json
benbenben tools status [id] --json
benbenben tools run <id> --json
```

tool 只能来自 `Runtime/manifest.json`。`executable` 必须位于 Runtime 内，argv 是固定数组，CLI 不接收模型追加的任意命令。非只读 action 在没有 `--yes` 时返回 `approvalRequired`。

## 兼容入口

旧 `benshell`、`notchwow` 和 `nw` 仍可使用，但只作为到统一 Runtime 的兼容转发器。兼容入口不代表产品继续使用旧品牌，也不应加入 PATH 的更高优先级。

旧 alias 对应关系保留如下，方便迁移记忆：

| alias | 当前入口 |
| --- | --- |
| `bbb` | `benbenben` |
| `bsh` | `benbenben` |
| `bshs` | `benbenben status` |
| `bshsync` | `benbenben sync` |
| `nb` | `nanobot` |
| `nbs` | `nanobot status` |
| `nbl` | `nanobot logs` |
| `nbsync` | `nanobot sync` |
| `dt` | `deeptutor` |
| `dts` | `deeptutor status` |
| `dtl` | `deeptutor logs` |
| `dtsync` | `deeptutor sync` |
| `pap` | `papis` |
| `papd` | `papdoctor` |
| `papl` | `paplist` |
| `paps` | `papserve` |
| `papsync` | `papis sync` |
| `tap` / `tt` | `taptap` |
| `taps` | `taptap status` |
| `tapsync` | `taptap sync` |
| `nw` | `benbenben` |
| `nws` | `benbenben status` |
| `nwv` | `benbenben verify` |
| `nwsync` | `benbenben sync` |
| `aisync` | `bensync sync` |
| `aistatus` | `bensync status` |

`papdoctor`、`paplist`、`papserve` 等一键入口应继续由对应脚本的帮助块或 Runtime manifest 明确声明，不重新依赖不透明 alias。

## 验收

```bash
./Scripts/test-runtime.sh
benbenben runtime status --json
benbenben tools list --json
command -v benbenben
command -v notchwow
```

验收目标：

- App bundle 脱离源码 checkout 后仍包含完整 Runtime。
- 新 Terminal 的 `benbenben` 指向 `Runtime/current/bin/benbenben`。
- App 与 Terminal 显示相同 Runtime 版本和 catalog。
- 旧 `/Users/ben/Desktop/Benshell` 不再排在 PATH 前面。
- 重复运行迁移不会重复写入 `~/.zshrc`。
