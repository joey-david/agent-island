#!/bin/bash
# Build, install to ~/Applications and wire up Claude Code + Codex hooks.
#   curl -fsSL https://raw.githubusercontent.com/joey-david/topnotchers/master/install.sh | bash
# Piped like that, it fetches the source into ~/.topnotchers/src first. Homebrew's
# topnotchers-setup runs it with PREBUILT set to the already-built app and hook.
set -euo pipefail
HOME_DIR="$HOME/.topnotchers"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || pwd)"
if [ -z "${PREBUILT:-}" ] && [ ! -f "$HERE/build.sh" ]; then
  xcrun --find swiftc >/dev/null 2>&1 || { echo "Topnotchers builds from source: run 'xcode-select --install' first."; exit 1; }
  SRC="$HOME_DIR/src"
  if [ -d "$SRC/.git" ]; then git -C "$SRC" pull -q --ff-only; else mkdir -p "$HOME_DIR"; git clone -q --depth 1 https://github.com/joey-david/topnotchers.git "$SRC"; fi
  exec bash "$SRC/install.sh"
fi
cd "$HERE"
if [ -n "${PREBUILT:-}" ]; then OUT="$PREBUILT"; else ./build.sh; OUT=build; fi
# Formerly Agent Island: carry its config and sprites over, and leave the old paths working for
# agents that started with the old hooks.
OLD="$HOME/.agent-island"
if [ -d "$OLD" ] && [ ! -L "$OLD" ] && [ ! -e "$HOME_DIR" ]; then
  pkill -x AgentIsland 2>/dev/null && sleep 0.3 || true
  mv "$OLD" "$HOME_DIR"
  ln -s "$HOME_DIR" "$OLD"
  ln -sf topnotchers-hook "$HOME_DIR/bin/island-hook"
  rm -f "$HOME_DIR/island.sock"
  rm -rf "$HOME/Applications/Agent Island.app"
fi
mkdir -p "$HOME_DIR/bin" "$HOME_DIR/sprites" "$HOME/Applications"
install -m 755 "$OUT/topnotchers-hook" "$HOME_DIR/bin/topnotchers-hook"
python3 -I tools/extract_pets.py "$HOME_DIR/sprites" || echo "no Codex pets found (ChatGPT.app missing?)"
python3 -I tools/install_hooks.py

pkill -x Topnotchers 2>/dev/null && sleep 0.3 || true
rm -rf "$HOME/Applications/Topnotchers.app"
cp -R "$OUT/Topnotchers.app" "$HOME/Applications/"

# The app registers itself to open at login (toggle in its menu).
open "$HOME/Applications/Topnotchers.app"
echo "Topnotchers installed."
