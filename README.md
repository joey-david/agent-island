# Agent Island

A Dynamic Island for coding agents on a notched MacBook.

![Agent Island demo](docs/demo.gif)

- **One mascot per session**, peeking out from behind the notch — Clawd for Claude Code,
  the Codex pet for Codex. They work, wave when they need you, and jump when they're done.
  Extra sessions of the same agent stack up behind the first.
- **Hover** a side and it widens to show each agent's task, latest action and 5-hour usage.
  ←/→ walk through sessions, Return opens one, Esc closes. Hovering marks finished work as read.
- **Click** a mascot to jump to its Ghostty tab, or the Codex app thread.
- **Quick decisions in place:** Claude's multiple-choice questions and permission prompts
  widen the island, then drop a panel you can answer without leaving what you're doing.

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

## Demo

```sh
./demo.sh
```

Plays the tour above with throwaway sessions (your own agents are hidden meanwhile and your
config is restored afterwards). Answer the question in the island when it asks.
Full-quality recording: [docs/demo.mp4](docs/demo.mp4).

## Agents

Up to 10, configured in `~/.agent-island/config.json` or from the menu-bar item
(side: left / right / hidden; sprite: `clawd`, any Codex pet, or a path to a v2 pet atlas).
Any agent can report in:

```sh
island-hook --agent <id> [--wait]          # Claude-style hook JSON on stdin
island-hook emit --agent <id> --state working|question|done|end \
  [--session S] [--cwd DIR] [--prompt TASK] [--action TEXT] [--pid PID]
```

Sessions end with SessionEnd, `--state end`, or when their process exits.

Debug log: `touch ~/.agent-island/events.log`.
