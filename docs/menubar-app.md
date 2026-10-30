# Menu bar app (Swift)

## Role

Show **one light per open VS Code window**, in the project's color, reflecting the most urgent Claude Code or Codex state in that project. On click, bring the right VS Code window to the front and make it fill the screen.

## Shape

- Agent app: no Dock icon, no window (`LSUIElement`).
- One `NSStatusItem` per file in `~/.cuelight/windows/`, added or removed as those files appear or disappear. Each one is a separate button, 12 pt wide (the size of the light) instead of the standard square width, so the lights take less room. Don't group them into a single item: the whole button gets highlighted and clicks no longer reach the right light (tried and dropped).
- Color computed with the algorithm in [color.md](color.md) (same palettes and test vectors as the extension).
- Started by the VS Code extension when a window opens (`open -g -b com.louisbadr.cuelight`), not at login.
- The same binary is the Claude Code and Codex hook (`Cuelight hook <agent>`, see [claude-hooks.md](claude-hooks.md) and [codex-hooks.md](codex-hooks.md)).

## Automatic setup

On every launch, in the background, the app installs whatever is missing (nothing happens if everything is in place):
1. the `~/.cuelight/bin/cuelight` link to its binary;
2. the hooks in `~/.claude/settings.json` and `~/.codex/hooks.json` (backup, then merge; see [claude-hooks.md](claude-hooks.md) and [codex-hooks.md](codex-hooks.md));
3. the VS Code extension: if `~/.vscode/extensions/louisbadr.cuelight-<version>` doesn't exist, it runs `code --install-extension cuelight.vsix --force` with the `.vsix` embedded in `Contents/Resources`.

A plain link in `~/.vscode/extensions` isn't enough: VS Code keeps a registry (`extensions.json`) and ignores folders dropped there by hand.

## Drawing the states

| State | Drawing |
|---|---|
| no agent | empty ring, project color |
| `idle` | pale disc (project color at 30%): nothing to do |
| `working` | loading spinner: the pale disc, with an arc turning along its edge (one turn per second, redrawn 30 times a second) |
| `done` | solid disc, project color: the light is on, a result is waiting to be seen |
| `waiting` | solid disc with a white dot in the center, to catch the eye |

The light is drawn by hand (not a template image), since the color is the information.

## Clicking a light

**Left click: the project's VS Code window comes to the front and fills the screen.**

"Fills the screen" means **not** macOS full screen: the menu bar and the Dock stay visible, no dedicated Space. It is the equivalent of macOS *Window → Fill*.

1. Run `open -a "Visual Studio Code" <path>`. VS Code reuses the window already open on this folder and brings it to the front.
2. After 0.6 s, through the Accessibility API (`AXUIElement`): set the focused window's `AXPosition` and `AXSize` to the visible area of its screen (`NSScreen.visibleFrame`, which excludes the menu bar and the Dock). `NSScreen` has its origin at the bottom left, the Accessibility API at the top left of the main screen: convert.

This needs the **Accessibility** permission (System Settings → Privacy & Security). Without it, the click only brings the window to the front. Each rebuild changes the app's ad hoc signature, so macOS may ask for the permission again: remove Cuelight from the list and add it back.

**Right click: menu.**

```
my-app  ·  Agent needs you
─────────────────────────────
Palette  ▸  Pastel ✓ / Soft / Vivid
─────────────────────────────
Quit Cuelight
```

The palette is saved in `~/.cuelight/settings.json` (see ARCHITECTURE.md). The app redraws its lights right away, and the extension recolors the title bar within about a second.

## Reading the state folder

- Every second, the app re-reads `windows/` and `sessions/`.
- Windows and sessions whose `pid` no longer exists are deleted.
- An unreadable or incomplete file is skipped and retried on the next pass; the app never crashes on it.

## Order of the lights

By opening order (`openedAt`).

## Stack

Swift + AppKit (`NSStatusItem`, `AXUIElement`), a single file compiled with `swiftc` by `build.sh`, which assembles the `.app` bundle by hand (`Info.plist` with `LSUIElement`, icon, ad hoc signature). No Xcode project.
