# notchwow Automation Workspace

This directory contains user automation managed with notchwow.

Before editing scripts or plist files, read `~/Desktop/notchwow/docs/AUTOMATION_AGENT_GUIDE.md` when that repository is available.

## Directory Contract

- Put Shell scripts in `shs/workspace-scripts/*.sh`.
- Put Python scripts in `pys/*.py`.
- Put AppleScript files in `applescripts/*.applescript`.
- Put launchd plist files in `launchds/com.notchwow.<task>.plist`.
- Treat `shs/workspaces/`, `shs/workspace-inputs/`, transcript files, and log files as runtime output unless the task explicitly concerns them.

## Script Rules

- Resolve the workspace with `KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"`; do not hardcode `/Users/ben`.
- Use absolute paths in launchd `ProgramArguments`.
- Use `/bin/zsh` for Shell scripts, the configured Conda Python for Python scripts, and `/usr/bin/osascript` for AppleScript files.
- Keep scripts idempotent, quote paths, emit useful errors to stderr, and avoid embedding secrets.
- Use `com.notchwow.` for launchd labels.
- Do not load, unload, or delete launchd jobs without explicit approval.

## Architecture

- Keep Shell files as small entrypoints. Source `shs/workspace-scripts/automation-common.sh` for environment setup.
- Put structured state handling and non-trivial business logic in `pys/*.py`.
- Use AppleScript only for macOS UI integration such as notifications, window management, quick notes, and opt-in message drafts.
- Keep generated JSON, logs, PID files, and locks under `shs/workspaces/`.
- Prefer deterministic local generation. AI and network calls may enhance a task, but a scheduled job should still produce an inspectable result when they fail.

## Safety Defaults

- Scheduled jobs must not rewrite papis metadata, commit or push repositories, delete files, or send chat messages automatically.
- Treat GUI automation as draft-only unless the user explicitly requests the final irreversible action.
- For daily artifacts, check the dated directory or filename first. If today's artifact is absent, build it immediately; otherwise keep reruns idempotent.
- Write every human-readable AI or automation report as `.html`. Use JSON only for machine state; do not use Markdown as the final report format.
- Updating a plist does not reload an already running job. Do not run `launchctl bootstrap` or `bootout` without explicit approval.

## Validation

- Shell: `zsh -n path/to/script.sh`
- Python: `python -m py_compile path/to/script.py`
- AppleScript: `osacompile -o /tmp/notchwow-check.scpt path/to/script.applescript`
- launchd: `plutil -lint path/to/com.notchwow.task.plist`

After a broad automation change, also run:

```bash
/bin/zsh ~/keyoti/shs/workspace-scripts/keyoti-doctor.sh
```
