# Project: notchwow

macOS menubar app (Swift, SwiftPM). Binary lives at `dist/notchwow.app/Contents/MacOS/notchwow`.

## After every code change — mandatory steps

1. **Build**: `swift build`
2. **Copy binary**: `cp -f .build/debug/notchwow dist/notchwow.app/Contents/MacOS/notchwow`
3. **Restart app**: `pkill -x notchwow; sleep 0.3; open dist/notchwow.app`
4. **Git commit**: stage changed source files and commit with a concise message
5. **Do NOT push** unless explicitly asked

All 4 steps are required every time. No exceptions. Do not wait for the user to remind you.
