# Benshell 迁移说明

## 结果

`/Users/ben/Desktop/Benshell/scripts` 已迁入 notchwow 仓库：

```text
Scripts/benshell/
├── README.md
├── scripts/
│   ├── benshell
│   ├── bensync
│   ├── deeptutor
│   ├── nanobot
│   ├── notchwow
│   ├── papis
│   ├── taptap
│   └── lib/project-git.zsh
└── zsh/
    ├── exports.zsh
    ├── init.zsh
    └── functions/
```

`WorkspacePaths.benshellRoot` 默认指向 `Scripts/benshell`。如果用户设置里仍保存旧默认 `/Users/ben/Desktop/Benshell`，启动时会迁移到新的集成目录；手动覆盖过的自定义路径会保留。

## 命令发现

Scripts 模块不再读取 `zsh/aliases/*.zsh` 作为命令来源。命令列表来自：

- `Scripts/benshell/scripts/*` 中的 `Commands:` 或 `Controller commands:` 帮助块。
- `~/keyoti/shs/workspace-scripts/*.sh`，归入 `Shell scripts` toolkit。
- `~/keyoti/applescripts/*.applescript`，归入 `AppleScripts` toolkit。

命令点击后由 Terminal.app 启动。预览区会显示 command、cwd、env 和 source，便于确认启动上下文。

## Alias 清点

旧 alias 不再作为 notchwow 命令入口，但对应关系保留如下，方便手动迁移记忆：

| alias | 目标命令 |
| --- | --- |
| `bsh` | `benshell` |
| `bshs` | `benshell status` |
| `bshsync` | `benshell sync` |
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
| `tap` | `taptap` |
| `tt` | `taptap` |
| `taps` | `taptap status` |
| `tapsync` | `taptap sync` |
| `nw` | `notchwow` |
| `nws` | `notchwow status` |
| `nwv` | `notchwow verify` |
| `nwsync` | `notchwow sync` |
| `aisync` | `bensync sync` |
| `aistatus` | `bensync status` |

`papdoctor`、`paplist` 和 `papserve` 如果仍需要作为一键入口，应补进 `papis` 脚本的 `Commands:` / `Controller commands:` 帮助块，而不是重新依赖 alias。
