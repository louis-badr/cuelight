# Claude Code hooks

Claude Code's official hook mechanism, configured in `~/.claude/settings.json` (user level, so active in every project).

> Check event and field names against the [current Claude Code documentation](https://code.claude.com/docs/en/hooks) before changing the code: they evolve.

## Claude's state

Claude Code runs a command at certain moments and passes it a JSON object on stdin (with `session_id`, `cwd`, `hook_event_name`, among others). One hook handles every event and writes `~/.cuelight/sessions/<session_id>.json`.

Claude Code also exports its process ID to hooks in the **`CLAUDE_PID`** environment variable (undocumented, but checked in practice: it is the `claude` process). The hook writes it to the session file (`pid` field), and the app checks that it is alive: a session whose process is gone is ignored. This is more reliable than a timeout.

| Event | New state |
|---|---|
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `working` |
| `SubagentStart` | `working` |
| `PreToolUse` / `PostToolUse` | `working` (goes back from `waiting` to `working` once a permission is granted) |
| `Notification` of any type except `idle_prompt` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`…) | `waiting` |
| `Notification` of type `idle_prompt` | no change: it comes after a `Stop`, and rewriting the state would bring back a `done` result already seen |
| `PermissionRequest` | `waiting` (same as `permission_prompt`, more direct) |
| `Stop` | `done` (Claude finished, result to look at) |
| `StopFailure` | `done` (turn ended on an API error) |
| `SubagentStop` | not registered: it comes right after the turn's `Stop` and must neither restart `working` nor clear `waiting` |
| `SessionEnd` | delete the file |

The hooks are **not** declared `"async": true`: in the background, two close events (`PreToolUse` then `PermissionRequest`) could be written out of order. The hook takes a few milliseconds, which is negligible. Note that `SessionEnd` has only 1.5 s for all its hooks.

Implementation: **the app's binary itself**, run in hook mode (`Cuelight hook`, `runHook` in `menubar-app/main.swift`). It parses the JSON with `JSONSerialization` and copies the event into the `event` field. For `Notification`, it simply looks for `idle_prompt` in the raw text, so it doesn't depend on the exact name of the type field. It exits before starting AppKit: about 4 ms per call.

Command registered in `settings.json` for each event:

```
~/.cuelight/bin/cuelight hook 2>/dev/null || true
```

- `~/.cuelight/bin/cuelight` is a link to the app's binary, recreated on every app launch. If the app moves, only the link changes, not `settings.json`.
- `|| true`: even if the app was deleted, the hook exits with code 0 and prints nothing.
- `matcher: "*"` for `PreToolUse`, `PostToolUse` and `PermissionRequest`, no matcher for the others.

Hook constraints:
- **Fast** (a few ms): it runs often, and some hooks block Claude while they run.
- **Never fail loudly**: always exit with code 0, even if the state folder doesn't exist. A failing hook must not get in Claude's way.
- Atomic writes (temporary file + `rename`).
- Nothing on stdout: for `UserPromptSubmit` and `SessionStart`, stdout is added to Claude's context.

## Known limitation

Interrupting Claude with Esc may not fire `Stop`. If it doesn't, the session stays `working` until the next prompt, since the process is still alive.

## Installation

Done by the app on every launch (`updateClaudeHooks` in `menubar-app/main.swift`):
- reads `~/.claude/settings.json`; if it isn't strict JSON, leaves it alone;
- for each event, removes our old entries (found by the `.cuelight/bin/cuelight hook` marker in the command) and adds ours, without touching other tools' hooks;
- writes only if the result differs. In that case, first copies the file to `settings.json.cuelight-backup-<date>`, then writes atomically (sorted keys).

`Cuelight uninstall` (called by `install.sh --uninstall`) does the reverse: it removes our entries, with the same backup.

Claude Code picks up modified hooks by itself; if not, restart the session.

## Reference: ClaudeBar

[tddworks/ClaudeBar](https://github.com/tddworks/ClaudeBar) also tracks session state, but has no per-project lights and no link to VS Code. Its `HookInstaller.swift` shows how to install hooks next to other tools' hooks (found by a marker in the command). Design difference: its hooks send the JSON over HTTP to a server in the app. Cuelight uses files, so nothing is lost while the app isn't running.
