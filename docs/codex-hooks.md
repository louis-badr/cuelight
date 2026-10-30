# Codex hooks

Cuelight uses Codex's lifecycle hooks, shared by the CLI and the VS Code extension. The app merges its entries into the user-level `~/.codex/hooks.json`; existing hooks and top-level keys are preserved.

Codex requires users to review and trust new or changed hooks before they run. After installing Cuelight, approve the Cuelight entries in Codex's hook review when prompted. This trust step cannot and should not be bypassed by Cuelight.

## State mapping

The hook receives a JSON event on stdin and writes `~/.cuelight/sessions/codex-<session_id>.json`.

| Event | New state |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `working` |
| `SubagentStart` | `working` |
| `PreToolUse` / `PostToolUse` | `working` |
| `PermissionRequest` | `waiting` |
| `Stop` | `done` |
| `Interrupt` | `done` |
| `SessionEnd` | delete the file |

The installed command is synchronous and intentionally tiny:

```sh
~/.cuelight/bin/cuelight hook codex 2>/dev/null || true
```

It produces no stdout, always exits successfully, and writes state atomically. Codex does not expose the host process ID in hook input, so normal cleanup relies on `SessionEnd`. The app also drops a PID-less state file after 24 hours to recover from a crashed client.

## Installation and removal

On launch, Cuelight:

1. reads `~/.codex/hooks.json` if it exists;
2. leaves the file untouched if it is not valid JSON or an event has an unexpected shape;
3. removes stale Cuelight entries and appends the current entries without changing other hooks;
4. backs up an existing file as `hooks.json.cuelight-backup-<date>` before writing.

`Cuelight uninstall` removes only entries whose command contains `.cuelight/bin/cuelight hook`, using the same backup behavior.

Reference: [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).
