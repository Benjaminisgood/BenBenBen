# BenBenBen Automation Workspace

This directory contains personal automation managed with BenBenBen.

Before editing scripts or plist files, read `/Users/ben/Desktop/BenBenBen/docs/AUTOMATION_AGENT_GUIDE.md` when that repository is available.

## Directory Contract

- Put Shell scripts in `shs/workspace-scripts/*.sh`.
- Put Python scripts in `pys/*.py`.
- Put AppleScript files in `applescripts/*.applescript`.
- Put new launchd plist files in `launchds/com.benbenben.<task>.plist`.
- Put every human-readable generated report under `html/` so the HTML shared window can discover it.
- Existing `launchds/com.notchwow.<task>.plist` files are outside the current managed namespace: keep their filename, Label, and loaded state unless the user explicitly approves an exact change.
- Treat `shs/workspaces/`, `shs/workspace-inputs/`, transcript files, and log files as runtime output unless the task explicitly concerns them.

## Script Rules

- Resolve the workspace with `KEYOTI_HOME="${KEYOTI_HOME:-$HOME/keyoti}"`; do not hardcode `/Users/ben` inside reusable scripts.
- Use absolute paths in launchd `ProgramArguments`.
- Use `/bin/zsh` for Shell scripts, the configured Conda Python for Python scripts, and `/usr/bin/osascript` for AppleScript files.
- Keep scripts idempotent, quote paths, emit useful errors to stderr, and avoid embedding secrets.
- Use `com.benbenben.*` for new launchd labels.
- Never automatically rename, unload, reload, or delete `com.notchwow.*` Jobs.
- Do not load, unload, reload, or delete any launchd Job without explicit approval.

## Architecture

- Keep Shell files as small entrypoints. Source `shs/workspace-scripts/automation-common.sh` for environment setup.
- Put structured state handling and non-trivial business logic in `pys/*.py`.
- Use AppleScript only for macOS UI integration such as notifications, window management, quick notes, and opt-in message drafts.
- Keep generated JSON, logs, PID files, and locks under `shs/workspaces/`.
- Prefer deterministic local generation. AI and network calls may enhance a task, but a scheduled Job should still produce an inspectable result when they fail.
- For AI content, prefer the read-only Codex CLI gateway and fall back to OpenCode. Never turn model output into arbitrary shell commands.

## Safety Defaults

- Scheduled Jobs must not rewrite Papis metadata, commit or push repositories, delete files, or send chat messages automatically.
- Treat GUI automation as draft-only unless the user explicitly requests the final irreversible action.
- For daily artifacts, check the dated directory or filename first. If today's artifact is absent, build it immediately; otherwise keep reruns idempotent.
- Write every human-readable AI or automation report as `.html` under `~/keyoti/html/`. Use JSON only for machine state; do not use Markdown as the final report format.
- Treat Markdown notes as read-only sources. Write note-derived exercise pages to `~/keyoti/html/note-exercises/`; never write them back into `~/keyoti/mds/`.
- Updating a plist does not reload an already running Job. Do not run `launchctl bootstrap`, `bootout`, or `kickstart` without explicit approval.
- Respect BenBenBen file locks. Never bypass them with `chmod` or `chflags`.
- Runtime actions must use fixed IDs and argv from the BenBenBen manifest; never turn model text into arbitrary shell.

## Validation

- Shell: `zsh -n path/to/script.sh`
- Python: `python -m py_compile path/to/script.py`
- AppleScript: `osacompile -o /tmp/benbenben-check.scpt path/to/script.applescript`
- New launchd Job: `plutil -lint path/to/com.benbenben.task.plist`
- Protected launchd Job: `plutil -lint path/to/com.notchwow.task.plist`

After a broad automation change, also run:

```bash
/bin/zsh ~/keyoti/shs/workspace-scripts/keyoti-doctor.sh
```
