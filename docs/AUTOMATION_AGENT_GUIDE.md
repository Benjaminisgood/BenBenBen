# BenBenBen 自动化 Agent 指南

这份文档用于指导生成 Shell、Python、AppleScript 和 `launchd` plist 的 Agent。BenBenBen 把脚本编辑、受控运行和 Jobs 编排放在同一个工作台中，但脚本源文件与运行产物必须分开管理。

## 1. 安装工作区说明

仓库提供可下发到 `~/keyoti` 的 `AGENTS.md` 模板：

```bash
./Scripts/install-keyoti-agent-guide.sh
```

默认不会覆盖已有 `~/keyoti/AGENTS.md`。需要同步模板更新时显式执行：

```bash
FORCE=1 ./Scripts/install-keyoti-agent-guide.sh
```

主应用仓库路径是 `/Users/ben/Desktop/BenBenBen`。新的自动化配置不得引用其他历史 checkout。

## 2. 目录约定

| 类型 | 源文件位置 | 运行方式 |
| --- | --- | --- |
| HTML | `~/keyoti/html/**/*.html` | HTML 共同窗口直接预览 |
| Shell | `~/keyoti/shs/workspace-scripts/*.sh` | `/bin/zsh /absolute/path/script.sh` |
| Python | `~/keyoti/pys/*.py` | Settings 中配置的 Conda Python |
| AppleScript | `~/keyoti/applescripts/*.applescript` | `/usr/bin/osascript /absolute/path/script.applescript` |
| 新 Jobs | `~/keyoti/launchds/com.benbenben.<task>.plist` | Jobs 工作区加载和卸载 |
| 非当前命名空间 Jobs | `~/keyoti/launchds/com.notchwow.<task>.plist` | 不管理；保持现状 |

Shell 的 `workspaces/`、`workspace-inputs/`、transcript 和日志属于运行产物。Agent 不应把业务脚本写入这些目录。

推荐三层结构：

1. `shs/workspace-scripts/*.sh` 只解析少量参数、设置环境变量和调用下一层。
2. `pys/*.py` 负责结构化数据、状态持久化、内容生成和复杂业务逻辑。
3. `applescripts/*.applescript` 只负责通知、窗口控制、快速笔记等 macOS UI 交互。

五个共同窗口按以下协作链工作：MD 是只读知识源；PLIST 只调度固定 Shell 入口；SCRIPTS 负责薄入口和 macOS UI 适配；PY 处理业务逻辑与 JSON 状态；所有人读产物统一落入 HTML 模块。机器状态继续写入 `shs/workspaces/`。

避免在 Shell 中内嵌大段 Python，也不要把业务 Python 放进 Shell 目录下的隐藏缓存目录。

## 3. 脚本互调

Shell 脚本使用动态根目录，避免写死用户名：

```bash
KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"
/bin/zsh "$KEYOTI_HOME/shs/workspace-scripts/prepare.sh"
"$CONDA_ROOT/bin/python" "$KEYOTI_HOME/pys/report.py"
/usr/bin/osascript "$KEYOTI_HOME/applescripts/notify.applescript"
```

如果 Python 路径已在 Settings 中覆盖，plist 应使用配置后的绝对路径。生成前先查看 Settings 或 Jobs 上下文，不要假设固定安装位置。

建议让 Shell 入口统一 `source ~/keyoti/shs/workspace-scripts/automation-common.sh`。公共入口负责扩展 `launchd` 下较短的 PATH、解析 `KEYOTI_HOME` 与寻找 Python。

## 4. Jobs 编排与命名空间边界

新 plist 使用唯一的 `com.benbenben.*` Label，并在 `ProgramArguments` 中使用绝对路径。stdout 与 stderr 建议写入 `~/keyoti/launchds/` 下对应的 `.stdout.log` 和 `.stderr.log`。

`com.notchwow.*` 不属于当前管理命名空间，规则如下：

- 只可在用户明确指定文件时读取 plist 和服务状态。
- 不自动改名为 `com.benbenben.*`。
- 不自动 bootstrap、bootout、删除或替换。
- 不把新前缀的孤儿清理策略扩展到旧前缀。
- 只有用户明确要求迁移某个 Job 时，才先展示 plist Diff 和状态变化，再逐项确认执行。

修改已加载 Job 的 plist 不会改变正在运行的进程。文件编辑完成后先静态检查；只有用户明确批准 reload 时，才执行卸载和重新加载。

Agent 不得未经确认执行 `launchctl bootstrap`、`bootout`、`kickstart` 或删除操作。

## 5. Runtime action 安全边界

Codex 或其他 Agent 触发工具时，只能引用 `Runtime/manifest.json` 中的固定 action ID：

```text
id / title / summary / executable / arguments / cwd / risk / inputSchema
```

- executable 必须是 Runtime 内的相对路径。
- argv 必须来自 manifest，模型不能追加任意参数。
- `read` action 可直接运行；`write`、`execute` 和其他非只读 action 必须审批。
- Runtime 安装和 App 启动不得隐式执行 Brewfile、macOS defaults、Git sync/push、服务启动或端口清理。

## 6. 安全默认值

- 定时任务优先使用确定性的本地逻辑。AI 或网络请求可以增强结果，但不应成为生成基本产物的唯一方式。
- 自动化需要 AI 内容时首选只读 Codex CLI，失败后才尝试 OpenCode；两者都不可用时必须回退到确定性本地逻辑。Codex 自动化应隔离易漂移的个人配置，并使用只读 sandbox；模型输出不能直接变成任意 shell 命令。
- OpenCode 保底凭据只从环境变量或 macOS 钥匙串读取，默认钥匙串 service 为 `keyoti-dashscope-api-key`。每次调用使用临时 `OPENCODE_CONFIG` 覆盖并禁用 Shell、读写和编辑工具，不把 token 写回脚本、报告或日志。
- 定时任务默认不得自动修改文献元数据、提交代码、推送仓库或向联系人发送消息。
- Papis 等资料库适合定时做只读审计；写入必须由用户显式触发并检查差异。
- GUI 自动化默认只生成草稿。点击发送、删除、覆盖或执行不可逆动作前，需要显式参数或用户确认。
- 每日产物采用带日期目录或文件名，并先检查当天产物是否存在；重复运行保持幂等。
- 所有给人阅读的 AI 或自动化报告统一输出到 `~/keyoti/html/` 下的模块目录，并使用 `.html`。JSON 只用于机器状态，不把 Markdown 作为面向用户的最终报告格式。
- Markdown 笔记是只读知识源。笔记派生的练习页面写入 `~/keyoti/html/note-exercises/`，不得回写 `~/keyoti/mds/`。
- 文件锁保护的 Markdown、脚本和 plist 不可写；不要用 chmod/chflags 绕过锁。

## 7. 质量检查

```bash
zsh -n ~/keyoti/shs/workspace-scripts/task.sh
python -m py_compile ~/keyoti/pys/task.py
osacompile -o /tmp/benbenben-check.scpt ~/keyoti/applescripts/task.applescript
plutil -lint ~/keyoti/launchds/com.benbenben.task.plist
```

检查旧 Job 时保持原文件名和 Label：

```bash
plutil -lint ~/keyoti/launchds/com.notchwow.task.plist
```

脚本应可重复执行、正确引用带空格路径、把错误写入 stderr，并避免把 API Key、密码或 token 写入源码和 plist。

修改完整套自动化后，再运行：

```bash
/bin/zsh ~/keyoti/shs/workspace-scripts/keyoti-doctor.sh
```

需要真实验证两套 AI provider 时运行：

```bash
python3 ~/keyoti/pys/keyoti_doctor.py --ai-smoke
```

Codex 冒烟属于必需检查；OpenCode 冒烟是保底检查，会在凭据过期时明确报告为可选故障。
