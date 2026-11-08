# Menu bar app (Swift)

## Role

Show **one light per open VS Code window**, in the project's color, reflecting the most urgent Claude Code or Codex state in that project. On click, bring the right VS Code window to the front and make it fill the screen.

## Shape

- Agent app: no Dock icon, no window (`LSUIElement`).
- One `NSStatusItem` per file in `~/.cuelight/windows/`, added or removed as those files appear or disappear. Each one is a separate button, 12 pt wide (the size of the light) instead of the standard square width, so the lights take less room.
- Don't group them into a single item (tried twice and dropped). Since macOS 27 the system draws the menu bar itself: on a click it highlights the whole item and only calls the item's action, so subviews of the button never get the click and a single light can't be highlighted.
- Kept side by side: macOS puts a new icon at the left end of the icons, so an icon added between two lights created at different times (another app's, or a light for a window opened later) splits them. Half a second after the lights stop moving (`NSWindow.didMoveNotification`), the app compares the frames of their windows. If there is a gap, it removes all the lights and re-creates them at once, which puts them back side by side at the left end. It tries once until they are seen side by side again, so it can't loop if macOS keeps them apart (crowded menu bar).
- Each light gets a new `autosaveName` (`light-<UUID>`) when it is created. macOS puts an item back where an item of the same name was (a Cmd-drag position, for instance), which can be away from the other lights; with the default names (`Item-0`, `Item-1`…) re-created lights went back to their old places and stayed split. An item with a new name lands at the left end.
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
| `working` | loading spinner: the pale disc, with an arc turning along its edge (one turn per second, animated by Core Animation so the app doesn't wake up for each frame) |
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
Palette  ▸  Vivid ✓ / Pastel
─────────────────────────────
Quit Cuelight
```

The palette is saved in `~/.cuelight/settings.json` (see ARCHITECTURE.md). The app redraws its lights right away, and the extension recolors the title bar within about a second.

## Reading the state folder

- The app watches `~/.cuelight/`, `windows/` and `sessions/` (`DispatchSource` on the directories: atomic writes show up as renames) and re-reads them when they change, plus every 10 seconds as a fallback that also catches dead processes.
- Colors are recomputed only when `colors.json` or `settings.json` change.
- Windows and sessions whose `pid` no longer exists are deleted.
- An unreadable or incomplete file is skipped and retried on the next pass; the app never crashes on it.

## Order of the lights

By opening order (`openedAt`).

## Stack

Swift + AppKit (`NSStatusItem`, `AXUIElement`), a single file compiled with `swiftc` by `build.sh`, which assembles the `.app` bundle by hand (`Info.plist` with `LSUIElement`, icon, ad hoc signature). No Xcode project.
