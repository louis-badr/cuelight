# VS Code extension

## Role

1. When a window opens on a folder: compute the color from the project name (see [color.md](color.md)) and tint the title bar.
2. Declare the window in `~/.cuelight/windows/<id>.json` (format in [ARCHITECTURE.md](../ARCHITECTURE.md)), and keep its focus state up to date.
3. When the window closes: delete that file.
4. Start the menu bar app if it isn't running (`open -g -b com.louisbadr.cuelight`; `-g` keeps it in the background, and nothing happens if it is already running or not installed).

Nothing else. The extension knows nothing about Claude Code or Codex.

## Activation

- `activationEvents`: `onStartupFinished`.
- Does nothing if no folder is open (empty window).
- Multi-root workspace: uses the first folder.

## Tinting the title bar

VS Code can color a single window only through **workspace settings**, that is `.vscode/settings.json`. Keys in `workbench.colorCustomizations`:

- `titleBar.activeBackground`
- `titleBar.activeForeground`
- `titleBar.inactiveBackground`
- `titleBar.inactiveForeground`

Rules:
- **Merge, don't overwrite.** The file may hold other settings. Only these four keys are touched, through VS Code's configuration API (`ConfigurationTarget.Workspace`), which handles JSONC and comments.
- **Write only when the value differs**, so the file doesn't change on every launch (git, sync).
- Rewritten when `~/.cuelight/settings.json` changes (palette chosen in the app), polled every second with `fs.watchFile`, which survives atomic renames.

## Declaring the window

- On activation: write `windows/<id>.json` with `path`, `name`, `pid` (the extension host's `process.pid`), `openedAt` and the focus fields.
- On `onDidChangeWindowState`: rewrite it with `focused` and `lastFocusedAt`.
- In `deactivate`: delete the file. `deactivate` isn't guaranteed (crash, kill): that's why the app checks the `pid`.
- If the open folder changes without closing the window (`onDidChangeWorkspaceFolders`): delete the old file, write the new one, recolor.

## Stack

Plain JavaScript, no build and no dependencies. `build.sh` packages it as a `.vsix` (a zip with a manifest, without `vsce`) and puts it inside the app, which installs it. Not published on the Marketplace.

For the app to reinstall the extension after a change, **bump `version` in `package.json`**: the app only installs a version that isn't already present.
