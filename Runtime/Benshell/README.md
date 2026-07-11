# 构建个人 runtime layer

## 底层

* zsh
* starship
* zoxide
* fzf
* bat
* eza

⸻

## dotfiles 管理

直接上：chezmoi 别浪费时间自己造轮子。

## package 管理

* brew
* Brewfile

⸻

# shell结构（仅供参考）
Benshell/
├── README.md
├── bootstrap/
│   ├── install.sh
│   ├── brew.sh
│   └── macos.sh
│
├── zsh/
│   ├── init.zsh
│   │
│   ├── aliases/
│   │   ├── git.zsh
│   │   ├── python.zsh
│   │   ├── ai.zsh
│   │   └── tap.zsh
│   │
│   ├── functions/
│   │   ├── filesystem.zsh
│   │   ├── git.zsh
│   │   ├── ai.zsh
│   │   └── tap.zsh
│   │
│   ├── exports.zsh
│   ├── prompt.zsh
│   └── plugins.zsh
│
├── scripts/
│   ├── tapplot
│   ├── taprun
│   ├── papis
│   └── deploy
│
├── config/
│   ├── git/
│   ├── tmux/
│   ├── nvim/
│   └── starship/
│
└── docs/

## 参考
https://github.com/mathiasbynens/dotfiles.git

https://github.com/Lissy93/dotfiles.git

## 当前已接入：Benshell

`/Users/ben/Desktop/Benshell` 自身也通过同一套 Git 同步入口管理：

```bash
benshell status      # 查看 Benshell 的 Git 分支、远端、差异和本地改动
benshell sync        # 与 GitHub 双向同步已提交历史
benshell pull        # 拉取远端提交，使用 rebase/autostash
benshell push        # 推送已提交历史
```

短别名：

```bash
bsh      # benshell
bshs     # benshell status
bshsync  # benshell sync
```

## 当前已接入：nanobot

`/Users/ben/Desktop/nanobot` 通过 Benshell 接入 zsh：

```bash
source /Users/ben/Desktop/Benshell/zsh/init.zsh
```

打开新终端后可用：

```bash
nanobot start       # 启动 OpenAI API + gateway + 前端
nanobot stop        # 停止 screen 会话
nanobot restart     # 重启并清理默认端口
nanobot status      # 查看会话、端口、健康状态
nanobot logs        # 查看 /tmp/nanobot-run 日志
nanobot sync        # 与 GitHub 双向同步已提交历史
```

`nanobot start` 会同时启动 OpenAI-compatible API：

```text
http://127.0.0.1:1234/v1/chat/completions
```

短别名：

```bash
nb      # nanobot
nbs     # nanobot status
nbl     # nanobot logs
nbsync  # nanobot sync
```

辅助函数：

```bash
nbhome     # cd 到 /Users/ben/Desktop/nanobot
nbagent    # 从源码 venv 启动 nanobot agent
nbgateway  # 前台启动 nanobot gateway
nbserve    # 前台启动 nanobot serve --port 1234
nbstatus   # 查看 nanobot status
```

## 当前已接入：DeepTutor

`/Users/ben/Desktop/DeepTutor` 也通过 Benshell 接入 zsh。打开新终端后可用：

```bash
deeptutor start      # 后台启动 DeepTutor 后端 API + 前端
deeptutor stop       # 停止官方 start_web.py 记录的进程和 screen 会话
deeptutor restart    # 重启并清理当前配置端口
deeptutor status     # 查看会话、端口、健康状态
deeptutor logs       # 查看 /tmp/deeptutor-run/deeptutor.log
deeptutor api        # 前台启动后端 API
deeptutor sync       # 与 GitHub 双向同步已提交历史
```

短别名：

```bash
dt      # deeptutor
dts     # deeptutor status
dtl     # deeptutor logs
dtsync  # deeptutor sync
```

辅助函数：

```bash
dthome  # cd 到 /Users/ben/Desktop/DeepTutor
dtcli   # 从源码 venv 启动 deeptutor CLI
dtapi   # 前台启动 deeptutor 后端 API
```

## 当前已接入：Papis

`/Users/ben/Desktop/papis` 通过 Benshell wrapper 接入 zsh。打开新终端后可直接使用：

```bash
papis --version      # 使用 /Users/ben/Desktop/papis/.venv/bin/papis
papis doctor         # 检查当前文献库配置
papis list --all     # 列出全部文献
papis serve          # 前台启动本地网页服务，仍直通原 papis CLI
papis start          # 后台启动 papis serve
papis stop           # 停止后台 serve
papis status         # 查看后台 serve 状态
papis logs           # 查看 /tmp/papis-run/serve.log
papis sync           # 与 GitHub 双向同步已提交历史
```

默认项目和文献库：

```text
PAPIS_HOME=/Users/ben/Desktop/papis
PAPIS_LIBRARY_DIR=/Users/ben/Desktop/papis/library
PAPIS_SERVE_URL=http://127.0.0.1:8888/
```

短别名：

```bash
pap   # papis
papd  # papdoctor
papl  # paplist
paps  # papserve
papsync # papis sync
```

辅助函数：

```bash
paphome    # cd 到 /Users/ben/Desktop/papis
papdoctor  # papis doctor
paplist    # papis list --all
papserve   # papis serve --address 127.0.0.1 --port 8888
```

## 当前已接入：taptap

`/Users/ben/Desktop/taptaptap` 通过 Benshell wrapper 接入 zsh。默认使用现有 conda 环境，并通过 `python -m taptap` 运行 CLI，避开环境里损坏的 console script。

```bash
taptap --help        # 查看 TAP SDK CLI
taptap setup         # 确认或创建 conda env，并安装 editable 包
taptap status        # 查看 Python 包信息和 Git 状态
taptap cli --help    # 显式直通底层 taptap CLI
taptap sync          # 与 GitHub 双向同步已提交历史
```

默认项目和 Python 环境：

```text
TAPTAP_HOME=/Users/ben/Desktop/taptaptap
TAPTAP_CONDA_ENV=taptap
TAPTAP_PYTHON=/Users/ben/miniforge3/envs/taptap/bin/python
```

短别名：

```bash
tap      # taptap
tt       # taptap
taps     # taptap status
tapsync  # taptap sync
```

辅助函数：

```bash
taphome  # cd 到 /Users/ben/Desktop/taptaptap
tapcli   # taptap cli
```

## 当前已接入：notchwow

`/Users/ben/Desktop/notchwow` 通过 Benshell wrapper 接入 zsh。打开新终端后可直接使用：

```bash
notchwow status      # 查看 app 进程和 Git 状态
notchwow build       # swift build --product notchwow
notchwow run         # 构建、打包、签名并启动 app
notchwow verify      # 构建、启动并检查进程是否存在
notchwow test        # 运行 Scripts/test-logic.sh
notchwow sync        # 与 GitHub origin 双向同步已提交历史
```

短别名：

```bash
nw      # notchwow
nws     # notchwow status
nwv     # notchwow verify
nwsync  # notchwow sync
```

辅助函数：

```bash
nwhome  # cd 到 /Users/ben/Desktop/notchwow
nwtest  # notchwow test
nwrun   # notchwow run
```

## GitHub 双向同步

Benshell 和已接入项目都支持同一组 Git 命令：

```bash
benshell status
benshell pull
benshell push
benshell sync

nanobot git-status
nanobot pull
nanobot push
nanobot sync

deeptutor sync
papis sync
taptap sync
notchwow sync
```

也可以一次检查或同步全部项目：

```bash
bensync status
bensync sync
bensync sync benshell
bensync sync nanobot
bensync sync taptap
bensync sync notchwow
```

`sync` 的策略是：先 `fetch --prune`，如果本地落后就 `pull --rebase --autostash`，如果本地有已提交但未推送的 commit 就 `push -u`。未提交文件会保留在本地，并提示先 commit 后才能同步到 GitHub。
