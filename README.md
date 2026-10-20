# Topnotchers

Your coding agents, living in your Mac's notch.

![Topnotchers demo](docs/demo.gif)

Every Claude Code and Codex session gets a mascot that peeks out from behind the notch: Clawd for
Claude, the Codex pet for Codex. It appears when you start an agent and leaves when you quit it.

| State | What you see |
| --- | --- |
| **Working** | The mascot animates. Hover for the task, live action and 5-hour usage. |
| **Needs you** | An orange dot, and the question or permission prompt drops down from the notch. Answer right there. |
| **Done** | A hop and a green dot until you look. Click the mascot to jump to its Ghostty tab or app. |

Several sessions of one agent stack up; hover their dots or use ←/→ to flip between them. In full
screen the island hides with the menu bar and pops in when an agent finishes.

**Insanely light:** ~0.7% of one core while animating, ~42 MB of memory. Native AppKit, no
Electron, no polling: agents report in through hooks over a Unix socket.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/joey-david/topnotchers/master/install.sh | bash
# or
brew install joey-david/tap/topnotchers && topnotchers-setup
```

Apple silicon, macOS 14+, Xcode Command Line Tools. It builds on your machine (no Gatekeeper
warning), wires up the Claude Code and Codex hooks and starts at login. Then approve the hooks
once with `/hooks` in Codex, and let Topnotchers control Ghostty when macOS asks.

## Other agents

Up to 10, on either side, set from the menu-bar item or `~/.topnotchers/config.json`:

```sh
~/.topnotchers/bin/topnotchers-hook --agent <id>                       # Claude-style hook JSON on stdin
~/.topnotchers/bin/topnotchers-hook emit --agent <id> --state working  # or question, done, end
```

---

Made by Joey. Follow [@t0rt0ised](https://x.com/t0rt0ised), and if it saves you some
tab-switching, a ⭐ helps others find it.
