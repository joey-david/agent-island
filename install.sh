#!/bin/bash
# Build, install to ~/Applications and wire up Claude Code + Codex hooks.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
HOME_DIR="$HOME/.topnotchers"
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
install -m 755 build/topnotchers-hook "$HOME_DIR/bin/topnotchers-hook"
python3 -I tools/extract_pets.py "$HOME_DIR/sprites" || echo "no Codex pets found (ChatGPT.app missing?)"
python3 -I tools/install_hooks.py

pkill -x Topnotchers 2>/dev/null && sleep 0.3 || true
rm -rf "$HOME/Applications/Topnotchers.app"
cp -R "build/Topnotchers.app" "$HOME/Applications/"

# The app registers itself to open at login (toggle in its menu).
open "$HOME/Applications/Topnotchers.app"
echo "Topnotchers installed."
