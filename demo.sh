#!/bin/bash
# A scripted tour of Agent Island: fake Claude Code and Codex sessions start, work,
# stack up, ask you a question (answer it in the island), finish, and exit.
# Needs the app running and island-hook installed (./install.sh).
set -euo pipefail
H="$HOME/.agent-island/bin/island-hook"
[ -x "$H" ] || { echo "Run ./install.sh first."; exit 1; }
pgrep -x AgentIsland >/dev/null || { open -a "Agent Island" && sleep 1.5; }

# The demo runs its own two agents and hides your real ones; your config comes back on exit.
CONFIG="$HOME/.agent-island/config.json"
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
cleanup() {
  kill "${PIDS[@]}" 2>/dev/null || true
  sleep 0.8
  mv "$CONFIG.demo-backup" "$CONFIG"
}
trap cleanup EXIT
sleep 0.5

emit() { # agent session pid state cwd prompt action
  "$H" emit --agent "demo-$1" --session "demo-$2" --pid "$3" --state "$4" --cwd "$5" --prompt "$6" --action "$7"
}

spawn C1; spawn C2; spawn X1
P1="Build a notch monitor for coding agents"
P2="Tighten the hero section copy"
PX="Fix the flaky sync test"

echo "Claude starts working…"
emit claude a "$C1" working ~/projects/agent-island "$P1" "Reading Island.swift"; sleep 2.5
emit claude a "$C1" working ~/projects/agent-island "$P1" "Editing Sprites.swift"; sleep 1.5

echo "Codex joins on the right…"
emit codex a "$X1" working ~/projects/earned-time "$PX" "Running the server tests"; sleep 2.5

echo "A second Claude session stacks behind the first…"
emit claude b "$C2" working ~/projects/portfolio "$P2" "Editing index.html"; sleep 2.5
emit claude a "$C1" working ~/projects/agent-island "$P1" "Building the app"; sleep 2

echo "Claude has a question — answer it in the island."
"$H" --agent demo-claude --wait --pid "$C1" <<JSON >/dev/null
{"hook_event_name":"PreToolUse","session_id":"demo-a","cwd":"$HOME/projects/agent-island","tool_name":"AskUserQuestion",
 "tool_input":{"questions":[{"header":"Mascot","question":"Which mascot should sit on the right of the notch?","multiSelect":false,
 "options":[{"label":"Codex","description":"The official Codex pet"},{"label":"Hoots","description":"The owl"},{"label":"Dewey","description":"The tidy one"}]}]}}
JSON
emit claude a "$C1" working ~/projects/agent-island "$P1" "Applying your answer"; sleep 2

echo "Codex finishes…"
emit codex a "$X1" done ~/projects/earned-time "$PX" ""; sleep 2.5
echo "Both Claude sessions finish…"
emit claude b "$C2" done ~/projects/portfolio "$P2" ""; sleep 1
emit claude a "$C1" done ~/projects/agent-island "$P1" ""; sleep 3.5

echo "Agents exit, and the island tucks back behind the notch."
kill "$X1"; sleep 1.2; kill "$C2"; sleep 1.2; kill "$C1"; sleep 1
