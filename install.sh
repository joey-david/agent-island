#!/bin/bash
# Build, install to ~/Applications and wire up Claude Code + Codex hooks.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
HOME_DIR="$HOME/.agent-island"
mkdir -p "$HOME_DIR/bin" "$HOME_DIR/sprites" "$HOME/Applications"
install -m 755 build/island-hook "$HOME_DIR/bin/island-hook"
python3 -I tools/extract_pets.py "$HOME_DIR/sprites" || echo "no Codex pets found (ChatGPT.app missing?)"
python3 -I tools/install_hooks.py

pkill -x AgentIsland 2>/dev/null && sleep 0.3 || true
rm -rf "$HOME/Applications/Agent Island.app"
cp -R "build/Agent Island.app" "$HOME/Applications/"

# The app registers itself to open at login (toggle in its menu).
open "$HOME/Applications/Agent Island.app"
echo "Agent Island installed."
