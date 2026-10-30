# Architecture

## Overview

```
 VS Code (one window per project)        Claude Code / Codex (one or more sessions)
 ┌───────────────────────────┐           ┌───────────────────────────┐
 │ Cuelight extension        │           │ hooks → Cuelight hook     │
 │  - color = hash(name)     │           └─────────────┬─────────────┘
 │  - tints the title bar    │                         │
 │  - declares the window    │                         │
 └─────────────┬─────────────┘                         │
               │ windows/<id>.json                     │ sessions/<sid>.json
               ▼                                       ▼
        ┌──────────────────────── ~/.cuelight/ ────────────────────────┐
        └──────────────────────────────┬───────────────────────────────┘
                                       │ read every second
                                       ▼
                             Swift menu bar app
                  one light per open VS Code window, color = hash(name)
                  click → window to the front, filling the screen
```

Principles:
- **The color is never passed around.** The extension and the app each compute it from the project name with the same algorithm ([docs/color.md](docs/color.md)), so a project always has the same color.
- **Each producer writes only its own files**, and only the app reads all of them.
- The extension just says "this window is open on this folder". The app can't reliably list VS Code windows itself: the macOS Accessibility API doesn't always see windows on other Spaces, and matching a window title to a folder is fragile.

## The state folder `~/.cuelight/`

This is the contract between the pieces. Change this format here first, then in the code.

```
~/.cuelight/
├── bin/
│   └── cuelight              link to the app's binary, called by the hooks
├── windows/
│   └── <window-id>.json      written by the VS Code extension
├── sessions/
│   └── <agent>-<session-id>.json
│                              written by Claude Code or Codex hooks
├── settings.json             optional, written by the app (chosen palette)
└── colors.json               optional, written by hand (forced colors)
```

Common rules:
- Everything is UTF-8 JSON.
- **Atomic writes**: write to a temporary file in the same folder, then `rename`. The app must never read a half-written file.
- Dates are ISO 8601 UTC with milliseconds (JavaScript's `toISOString()`).
- `window-id` = the first 12 hex characters of the SHA-1 of the folder's absolute path, without a trailing `/`.

### `windows/<window-id>.json`

One file per VS Code window open on a folder. No color in it.

```json
{
  "path": "/Users/me/Projects/my-app",
  "name": "my-app",
  "pid": 41237,
  "openedAt": "2026-10-15T11:10:00.000Z",
  "focused": false,
  "lastFocusedAt": "2026-10-15T11:42:07.512Z"
}
```

- `pid`: the extension host process. The app checks that it is alive, to remove the light if VS Code crashed without cleaning up.
- `focused`: the window has the focus right now.
- `lastFocusedAt`: the last moment the window had the focus (updated when it gains and when it loses the focus). Missing if it never had it. Used to tell whether a `done` result was seen.
- Created when the window opens, rewritten on every focus change, deleted when it closes.

### `sessions/<agent>-<session-id>.json`

One file per Claude Code or Codex session, written by the hook (the app's binary run as `Cuelight hook claude` or `Cuelight hook codex`; see [docs/claude-hooks.md](docs/claude-hooks.md) and [docs/codex-hooks.md](docs/codex-hooks.md)).

```json
{
  "agent": "codex",
  "state": "working",
  "updatedAt": "2026-10-15T11:40:31.204Z",
  "pid": "",
  "event": { "session_id": "…", "cwd": "/Users/me/Projects/my-app", "hook_event_name": "PreToolUse", "…": "…" }
}
```

- `state` ∈ `idle` | `working` | `waiting` | `done`. `done`: the agent finished its turn (`Stop`). `idle`: nothing was asked yet in this session.
- `updatedAt`: when the hook wrote this `state`.
- `agent`: `claude` or `codex`.
- `pid`: the Claude Code process when available through `CLAUDE_PID`. Codex does not expose its host PID to hooks, so Codex records use an empty string and are removed by `SessionEnd` (or after 24 hours as crash recovery).
- `event`: the last event received, as is. The app reads `cwd` from it.
- Deleted when the session ends (`SessionEnd` hook).

### `colors.json` (optional)

Forces a project's color when two projects land on the same one. Read by the extension **and** the app.

```json
{ "my-app": "#F2A6A0" }
```

### `settings.json` (optional)

Settings chosen in the app's menu (right-click on a light). Written by the app, read by the extension **and** the app. Missing = defaults.

```json
{ "palette": "pastel" }
```

- `palette` ∈ `vivid` | `soft` | `pastel` (default `pastel`, also used for unknown values). See [docs/color.md](docs/color.md).
- The extension watches this file and recolors the title bar when it changes.

## Install and launch

- `install.sh` (run through `curl … | bash`) downloads the source, calls `build.sh` to make `Cuelight.app` (which embeds the VS Code extension as a `.vsix`), moves it to `~/Applications` and starts it. Run from a clone, it uses the local source.
- `install.sh --uninstall` runs `Cuelight uninstall` (removes the hooks and the extension), then deletes the app and `~/.cuelight/`.
- **On every launch**, the app installs whatever is missing: the `~/.cuelight/bin/cuelight` link, the hooks in `~/.claude/settings.json` and `~/.codex/hooks.json` (backup, then merge), and the VS Code extension (through the `code` CLI, if this version isn't installed yet). Codex asks the user to review and trust newly installed hooks before running them.
- **When a VS Code window opens**, the extension starts the app if it isn't running (`open -g -b com.louisbadr.cuelight`).

## Which lights to show

**One light per file in `windows/`**, that is per open VS Code window. An agent session with no matching VS Code window (terminal only) gets no light.

## Matching a session to a window

A session's `cwd` can be a subfolder of the project. The app matches each session to the window whose `path` is the **longest prefix** of its `cwd`.

## State of a light

- No matching session: *no agent* (drawn differently from `idle`, see [docs/menubar-app.md](docs/menubar-app.md)).
- Otherwise, the most urgent state among its sessions: `waiting` > `done` > `working` > `idle`.
- A `done` session counts as `idle` once its result was seen: the window has the focus (`focused`), or had it after the turn ended (`lastFocusedAt` ≥ the session's `updatedAt`). Clicking the light focuses the window, so it marks the result as seen.

A session whose `pid` no longer exists is dead and ignored.
