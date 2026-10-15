<p align="center"><img src="assets/icon.png" width="128" alt="Cuelight icon"></p>

# Cuelight

A colored light in the macOS menu bar for each VS Code window, showing what Claude Code is doing in that project. The same color tints the window's title bar, so you can tell at a glance which project needs you.

![Three VS Code windows with tinted title bars, and their lights in the menu bar](assets/overview.png)

Each light shows Claude's state in its project:

![Light states: no Claude, idle, working, done, needs you](assets/states.png)

Click a light to bring its VS Code window to the front and fill the screen. Right-click for the palette and Quit.

## Requirements

- macOS 13 or later
- VS Code, with the `code` command available
- Claude Code (CLI or the VS Code extension)
- Apple's command line tools (`xcode-select --install`)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/louis-badr/cuelight/main/install.sh | bash
```

This downloads the source, builds `Cuelight.app` on your Mac, puts it in `~/Applications` and starts it. Because it is built locally, macOS doesn't block it even though it isn't notarized.

On first launch, Cuelight sets up the rest by itself:

- adds its hooks to `~/.claude/settings.json`, after saving a backup next to it (`settings.json.cuelight-backup-<date>`). Your other settings and hooks are kept;
- installs its VS Code extension.

Then:

1. Allow Cuelight in **System Settings → Privacy & Security → Accessibility**. This is only needed to resize the window when you click a light.
2. Quit and reopen VS Code.

From then on, opening VS Code starts Cuelight.

If you use Peacock or a similar extension that colors the title bar, disable it. Both would write to the same settings.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/louis-badr/cuelight/main/install.sh | bash -s -- --uninstall
```

This removes the hooks from `~/.claude/settings.json` (after a backup), the VS Code extension, the app and `~/.cuelight/`.

## Good to know

- **Title bar colors** are written to each project's `.vscode/settings.json`. Add `.vscode/` to your global gitignore if you don't want them in your repositories.
- **Two projects with the same color:** force one in `~/.cuelight/colors.json`, then reload the VS Code window:
  ```json
  { "my-project": "#F2A6A0" }
  ```

## Build from source

```bash
git clone https://github.com/louis-badr/cuelight.git
cd cuelight
./install.sh        # build and install from this folder
./build.sh          # only build dist/Cuelight.app
```

How it works: [ARCHITECTURE.md](ARCHITECTURE.md).

## License

[MIT](LICENSE)
