#!/bin/bash
# A scripted tour of Agent Island with throwaway sessions: pop-out, live tray, stacking,
# a question, a permission prompt, finishing, and exiting. Answer in the island when asked.
# Your own agents are hidden meanwhile; your config comes back on exit.
set -euo pipefail
H="$HOME/.agent-island/bin/island-hook"
[ -x "$H" ] || { echo "Run ./install.sh first."; exit 1; }
pgrep -x AgentIsland >/dev/null || { open -a "Agent Island" && sleep 1.5; }

CONFIG="$HOME/.agent-island/config.json"
[ -f "$CONFIG.demo-backup" ] && mv "$CONFIG.demo-backup" "$CONFIG"   # an earlier run was interrupted
cp "$CONFIG" "$CONFIG.demo-backup"
python3 -I - "$CONFIG" <<'PY'
import json, sys
p = sys.argv[1]
c = json.load(open(p))
for a in c["agents"]:
    a["side"] = "hidden"
c["agents"] = c["agents"][:8] + [
    {"id": "demo-claude", "name": "Claude Code", "side": "left", "sprite": "clawd", "color": "#D77757"},
    {"id": "demo-codex", "name": "Codex", "side": "right", "sprite": "codex", "color": "#9DB8FF"},
]
json.dump(c, open(p, "w"), indent=2)
PY

# Each fake session lives as long as a sleep process; killing it is the agent exiting.
PIDS=()
spawn() { sleep 600 >/dev/null 2>&1 & PIDS+=($!); disown $!; printf -v "$1" %s $!; }
cleanup() { kill "${PIDS[@]}" 2>/dev/null || true; sleep 0.8; mv "$CONFIG.demo-backup" "$CONFIG"; }
trap cleanup EXIT INT TERM

say() { printf '%5.1fs  %s\n' "$SECONDS" "$1"; }
emit() { # agent session pid state cwd prompt action
  "$H" emit --agent "demo-$1" --session "demo-$2" --pid "$3" --state "$4" --cwd "$HOME/projects/$5" --prompt "$6" --action "$7"
}
spawn A; spawn B; spawn C; spawn X
PA="Build a notch monitor for coding agents"; PB="Tighten the landing page copy"; PC="Profile the sync server"
PX="Fix the flaky sync test"
SECONDS=0; sleep 1.5

say "Claude pops out from behind the notch and starts working"
emit claude a $A working agent-island "$PA" "Reading Island.swift"; sleep 2.5
say "Codex joins on the right"
emit codex a $X working earned-time "$PX" "Running the server tests"; sleep 3
say "Hover a side: it widens to show the task and live action"
emit claude a $A working agent-island "$PA" "Editing Sprites.swift"; sleep 1.5
emit claude a $A working agent-island "$PA" "Building the app"; sleep 1.5
say "More Claude sessions stack up behind the first"
emit claude b $B working portfolio "$PB" "Editing index.html"; sleep 1
emit claude c $C idle sync-server "$PC" ""; sleep 2
say "Hover again and use ←/→ to flip through sessions"
sleep 5

say "Claude has a question: the island expands into a panel"
"$H" --agent demo-claude --wait --pid "$A" >/dev/null <<JSON
{"hook_event_name":"PreToolUse","session_id":"demo-a","cwd":"$HOME/projects/agent-island","tool_name":"AskUserQuestion",
 "tool_input":{"questions":[{"header":"Mascot","question":"Which mascot should sit on the right?","multiSelect":false,
 "options":[{"label":"Codex","description":"The official pet"},{"label":"Hoots","description":"The owl"},{"label":"Dewey","description":"The tidy one"}]}]}}
JSON
emit claude a $A working agent-island "$PA" "Applying your answer"; sleep 2

say "Codex asks for permission"
"$H" --agent demo-codex --wait --pid "$X" >/dev/null <<JSON
{"hook_event_name":"PermissionRequest","session_id":"demo-a","cwd":"$HOME/projects/earned-time","tool_name":"Bash",
 "tool_input":{"command":"npm publish --dry-run"}}
JSON
emit codex a $X working earned-time "$PX" "Publishing a dry run"; sleep 2

say "Work finishes: a little jump and a green dot"
emit codex a $X done earned-time "$PX" ""; sleep 1
emit claude b $B done portfolio "$PB" ""; sleep 2
say "Hovering marks finished work as read"
sleep 3
emit claude a $A done agent-island "$PA" ""; sleep 2.5

say "Agents exit and the island tucks back behind the notch"
kill $X; sleep 0.9; kill $C; sleep 0.9; kill $B; sleep 0.9; kill $A; sleep 1.5
