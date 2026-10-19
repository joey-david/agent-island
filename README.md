# Agent Island

A Dynamic Island for coding agents on a notched MacBook. Each agent's mascot peeks out
from behind the notch while a session is open, animates while it works, waves when it has
a question, and jumps when it's done. Hover a side to open its tray (task, latest action,
5-hour usage); click a mascot to jump to its Ghostty tab or app. Claude's multiple-choice
questions and permission prompts can be answered right in the island.

Native AppKit + Core Animation, no polling: hooks talk to the app over a Unix socket, and
sprite animations run on the render server.

## Install

```sh
./install.sh
```

This builds `~/Applications/Agent Island.app`, installs `~/.agent-island/bin/island-hook`,
copies the Codex app's pets into `~/.agent-island/sprites`, adds hooks to
`~/.claude/settings.json` and `~/.codex/hooks.json` (backups: `*.bak-agent-island`), and
starts the app at login.

- **Codex:** approve the new hooks once with `/hooks` in Codex; until then it ignores them.
- **Ghostty:** allow Agent Island to control Ghostty when macOS asks (used to focus tabs and read titles).
- **Claude usage:** the status line writes `~/.agent-island/usage/claude.json`.

## Agents

Up to 10, configured in `~/.agent-island/config.json` or from the menu-bar item
(side: left / right / hidden; sprite: `clawd`, any Codex pet, or a path to a v2 pet atlas).
Any agent can report in:

```sh
island-hook --agent <id> [--wait]          # Claude-style hook JSON on stdin
island-hook emit --agent <id> --state working|question|done|end
```

Debug log: `touch ~/.agent-island/events.log`.
