# Cuelight repository guide

## Project

Cuelight is a macOS menu bar app that shows the state of Claude Code or Codex for each open VS Code project. It consists of a dependency-free VS Code extension and a single-file Swift/AppKit app. The Swift binary also acts as the lifecycle hook used by both agents.

Read `ARCHITECTURE.md` before changing the state-file contract or how sessions are matched to windows. Keep the color algorithm identical in `menubar-app/main.swift` and `vscode-extension/extension.js`; its test vectors are documented in `docs/color.md`.

## Build and verification

- Build without installing: `./build.sh`
- Install a local checkout: `./install.sh`
- Inspect shell scripts: `bash -n build.sh install.sh`
- Check JavaScript syntax: `node --check vscode-extension/extension.js`
- Check whitespace and patch errors: `git diff --check`

`./build.sh` requires macOS and Apple command line tools. It creates `dist/Cuelight.app`; do not commit `dist/`.

There is no dependency-install step and no generated source. Preserve that simplicity unless a change clearly requires otherwise.

## Change rules

- Preserve users' existing Claude and Codex hooks when installing or uninstalling Cuelight.
- Back up a hook configuration before changing it, and leave malformed or unexpected configuration untouched.
- Hook mode must remain fast, silent on stdout, and successful even when an event is incomplete.
- State files under `~/.cuelight/` must be UTF-8 JSON written atomically.
- Bump `vscode-extension/package.json` when a release should reinstall the bundled VSIX.
- Update the README, architecture, and the relevant file under `docs/` when behavior or the state contract changes.
