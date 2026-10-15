#!/bin/bash
# Installs Cuelight: builds the menu bar app from source and launches it.
# The app then installs the Claude Code hooks and the VS Code extension by itself.
#
#   curl -fsSL https://raw.githubusercontent.com/louis-badr/cuelight/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/louis-badr/cuelight/main/install.sh | bash -s -- --uninstall
#
# Also works from a clone: ./install.sh
set -euo pipefail

repo="louis-badr/cuelight"
app="$HOME/Applications/Cuelight.app"

fail() { echo "Cuelight: $*" >&2; exit 1; }

[ "$(uname)" = Darwin ] || fail "macOS only."

if [ "${1:-}" = "--uninstall" ]; then
  pkill -x Cuelight || true
  # The app removes its own hooks from ~/.claude/settings.json and the VS Code extension.
  if [ -x "$app/Contents/MacOS/Cuelight" ]; then "$app/Contents/MacOS/Cuelight" uninstall; fi
  rm -rf "$app" "$HOME/.cuelight"
  echo "Cuelight uninstalled."
  exit 0
fi

xcrun --find swiftc >/dev/null 2>&1 ||
  fail "Apple's command line tools are required. Run 'xcode-select --install', then run this command again."

# Source: the folder of this script when run from a clone, otherwise downloaded from GitHub.
script="${BASH_SOURCE[0]:-}"
if [ -n "$script" ] && [ -f "$(dirname "$script")/build.sh" ]; then
  src=$(cd "$(dirname "$script")" && pwd)
else
  echo "Downloading Cuelight…"
  src=$(mktemp -d)
  trap 'rm -rf "$src"' EXIT
  curl -fsSL "https://github.com/$repo/archive/refs/heads/main.tar.gz" | tar -xz -C "$src" --strip-components 1
fi

echo "Building…"
bash "$src/build.sh" >/dev/null

pkill -x Cuelight || true
mkdir -p "$HOME/Applications"
rm -rf "$app"
mv "$src/dist/Cuelight.app" "$app"
open "$app"

echo "Cuelight is installed and running."
echo "Quit and reopen VS Code to load the extension. From then on, VS Code starts Cuelight by itself."
