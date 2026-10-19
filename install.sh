#!/bin/bash
# Build, install to ~/Applications, wire up Claude Code + Codex hooks, start at login.
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

PLIST="$HOME/Library/LaunchAgents/fyi.joeydavid.agent-island.plist"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>fyi.joeydavid.agent-island</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$HOME/Applications/Agent Island.app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PL
open "$HOME/Applications/Agent Island.app"
echo "Agent Island installed."
