# 自动化 Agent 指南

这份文档用于指导生成 Shell、Python、AppleScript 和 `launchd` plist 的 agent。`notchwow` 把脚本编辑、直接运行和 Jobs 编排放在同一个工作台中，但脚本源文件与运行产物必须分开管理。

## 1. 安装工作区说明

仓库提供可下发到 `~/keyoti` 的 `AGENTS.md` 模板：

```bash
./Scripts/install-keyoti-agent-guide.sh
```

默认不会覆盖已有 `~/keyoti/AGENTS.md`。需要同步模板更新时显式执行：

```bash
FORCE=1 ./Scripts/install-keyoti-agent-guide.sh
```

## 2. 目录约定

| 类型 | 源文件位置 | 运行方式 |
| --- | --- | --- |
| Shell | `~/keyoti/shs/workspace-scripts/*.sh` | `/bin/zsh /absolute/path/script.sh` |
| Python | `~/keyoti/pys/*.py` | Settings 中配置的 Conda Python |
| AppleScript | `~/keyoti/applescripts/*.applescript` | `/usr/bin/osascript /absolute/path/script.applescript` |
| Jobs | `~/keyoti/launchds/com.notchwow.<task>.plist` | Jobs 工作区加载和卸载 |

Shell 的 `workspaces/`、`workspace-inputs/`，以及 transcript 和日志文件属于运行产物。agent 不应把业务脚本写入这些目录。

推荐采用三层结构：

1. `shs/workspace-scripts/*.sh` 只负责解析少量参数、设置环境变量和调用下一层。
2. `pys/*.py` 负责结构化数据、状态持久化、内容生成和较复杂的业务逻辑。
3. `applescripts/*.applescript` 只负责通知、窗口控制、快速笔记等 macOS UI 交互。

避免在 Shell 中内嵌大段 Python，也不要把业务 Python 放进 Shell 目录下的隐藏缓存目录。

## 3. 脚本之间互调

Shell 脚本使用动态根目录，避免写死用户名：

```bash
KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"
CONDA_ROOT="${CONDA_ROOT:-$HOME/miniforge3}"
/bin/zsh "$KEYOTI_HOME/shs/workspace-scripts/prepare.sh"
"$CONDA_ROOT/bin/python" "$KEYOTI_HOME/pys/report.py"
/usr/bin/osascript "$KEYOTI_HOME/applescripts/notify.applescript"
```

如果 Python 路径已在 Settings 中覆盖，plist 应使用配置后的绝对路径。生成前先查看 Settings 或 Jobs AI 上下文，不要假设固定安装位置。

建议让 Shell 入口统一 `source ~/keyoti/shs/workspace-scripts/automation-common.sh`。这个公共入口负责扩展 launchd 下较短的 `PATH`、解析 `KEYOTI_HOME` 与寻找 Python。

## 4. Jobs 编排

每个 plist 使用唯一的 `com.notchwow.` Label，并在 `ProgramArguments` 中使用绝对路径。stdout 与 stderr 建议写入 `~/keyoti/launchds/` 下对应的 `.stdout.log` 和 `.stderr.log` 文件。

Jobs 工作区会自动清理缺少本地 plist 的已加载 `com.notchwow.*` 服务。移动或重命名 plist 前先卸载任务。agent 不应未经确认直接执行 `launchctl bootstrap`、`bootout` 或删除操作。

修改已加载 Job 的 plist 不会立即改变正在运行的进程。完成文件编辑后，先执行静态检查；只有用户明确同意 reload 时，才执行卸载与重新加载。

## 5. 安全默认值

- 定时任务应优先使用确定性的本地逻辑。AI 或网络请求可以增强结果，但不应成为生成基本产物的唯一方式。
- 定时任务默认不得自动修改文献元数据、自动提交代码、自动推送仓库或自动向聊天联系人发送消息。
- Papis 等资料库适合定时做只读审计；需要写入时由用户显式触发并检查差异。
- GUI 自动化默认只生成草稿。真正点击发送、删除、覆盖或执行不可逆操作前，需要显式参数或用户确认。
- 对每日内容采用带日期目录或文件名，并先检查今天的产物是否存在。缺失时立即尝试构建，重复运行保持幂等。
- 所有给人阅读的 AI 或自动生成报告统一输出为 `.html`。JSON 只用于机器状态，不要把 Markdown 作为面向用户的最终报告格式。

## 6. 质量检查

生成或修改文件后至少执行对应检查：

```bash
zsh -n ~/keyoti/shs/workspace-scripts/task.sh
python -m py_compile ~/keyoti/pys/task.py
osacompile -o /tmp/notchwow-check.scpt ~/keyoti/applescripts/task.applescript
plutil -lint ~/keyoti/launchds/com.notchwow.task.plist
```

脚本应可重复执行、正确引用带空格路径、把错误写入 stderr，并避免把 API Key、密码或 token 写入源码和 plist。

修改完整套自动化后，再运行：

```bash
/bin/zsh ~/keyoti/shs/workspace-scripts/keyoti-doctor.sh
```
