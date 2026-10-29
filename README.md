# Session Launcher

A small macOS menu-bar app for finding Claude Code and Codex conversations and resuming them in a new iTerm tab, so you can close tabs without losing track of conversations.

Click the menu-bar icon, type a few letters of the title, project, note or last prompt, then press Return (or click a row). A new iTerm tab opens in the conversation's original project folder and runs `claude --resume <id>` or `codex resume <id>`.

## Features

- One list of Claude and Codex conversations: pinned first, then most recent.
- Each row shows the provider, title, project, time since last activity and **the last thing you asked**.
- **Pins** (★) and a one-line **next-step note** (✎) on any conversation. These are stored by the app in `~/Library/Application Support/SessionLauncher/marks.json`.
- Keyboard: type to search, ↑/↓ to move, Return to open, Esc to clear the search.
- Right-click a row to copy the resume command or show the project in Finder.
- A green dot means the conversation may already be open; opening it asks first. This is checked again at the moment you open it.
- The tab opens in the iTerm window whose tabs are in the closest folders. For example, `~/work/projects/*` conversations go to the window holding your projects tabs. If no window is a clear match, it uses the frontmost window.

## Build and run

Requires macOS 14+, Xcode (Swift 5.9+) and iTerm.

```sh
./scripts/build-app.sh
open "build/Session Launcher.app"
```

To keep it around, drag `build/Session Launcher.app` into `/Applications`. Launch at login isn't built in yet; you can add the app under System Settings › General › Login Items.

Run the tests with `swift test`.

### Permissions

The first time you open a conversation, macOS asks whether Session Launcher may control iTerm. Allow it. If you declined earlier, turn it on under **System Settings › Privacy & Security › Automation › Session Launcher › iTerm**.

The build script signs the app with your Apple Development certificate when one is available, so this permission survives rebuilds. With ad-hoc signing (`SIGN_IDENTITY=- ./scripts/build-app.sh`), macOS may ask again after each rebuild.

The app is not sandboxed, because it reads `~/.claude` and `~/.codex`.

## Where the data comes from

The app only reads provider data. It never writes, moves or deletes conversation files.

| | Claude Code | Codex |
|---|---|---|
| Sessions | `~/.claude/projects/<encoded-folder>/<session-id>.jsonl` | `threads` table in `~/.codex/state_<N>.sqlite` (highest N, opened read-only) |
| Shown | Interactive sessions with at least one typed prompt. SDK/print-mode runs and subagent transcripts are excluded | `source` of `cli` or `vscode` with a first message or name. Subagent, guardian and `exec` threads are excluded |
| Title | Custom title → AI title → first prompt → `project · id` | Thread name → title → first message → `project · id` |
| Last prompt | `last-prompt` record | Last typed user message, read from the end of the rollout file |
| "May be open" | Claude's live-process registry in `~/.claude/sessions/` | Updated in the last 2 minutes (Codex has no process registry, so this is a guess) |

Claude transcripts are scanned once per app launch (about a second for ~800 MB); later refreshes only read new lines. Codex last prompts load in the background after the list appears.

## Known limitations

- **Internal formats.** Neither tool has a supported listing API, so the app reads their internal files. If a future version changes the format, that provider shows an "Unsupported" banner instead of wrong data. The other provider keeps working.
- **Claude retention.** Claude Code may delete old transcripts after a cleanup period (`cleanupPeriodDays`). Conversations it has deleted can't be listed or resumed.
- **Moved or deleted folders.** If a project folder no longer exists, the app shows an error with the original path. Claude looks up a session by its original folder, so resuming from somewhere else wouldn't work anyway.
- **Codex "may be open"** is a timing guess. A conversation you closed in the last 2 minutes also triggers the prompt; click *Open Anyway*.
- **Archived Codex sessions** are hidden unless you tick *Show archived* (it only appears when there are some).
- If iTerm isn't running, the app launches it and uses its first window rather than adding a second tab (not yet tested by hand).

## Manual test checklist

- [x] Unit tests pass (`swift test`: readers, filtering, title fallback, unsupported formats, quoting, pins/notes)
- [x] Reads real local Claude and Codex data read-only, including last prompts
- [x] App bundle builds and passes `codesign --verify`
- [x] Open the menu-bar window and find Claude and Codex conversations by title and project
- [ ] Resume a Claude conversation in a new iTerm tab: correct folder and conversation
- [ ] Resume a Codex conversation in a new iTerm tab: correct folder and conversation
- [ ] Opening a conversation that's already running shows the "Already open?" prompt
- [ ] A conversation whose folder was removed shows an error with its path
- [ ] Resume from a folder whose name contains spaces or quotes
- [ ] With two iTerm windows (e.g. one for work, one for side projects), each conversation opens in the matching window
- [ ] Pin a conversation and add a note; both survive quitting and reopening the app
- [ ] Close and reopen the window; the list refreshes
- [ ] Declining iTerm Automation permission shows the System Settings hint
