# Topnotchers

Your coding agents, living in your Mac's notch.

![Topnotchers demo](docs/demo.gif)

Every Claude Code and Codex session gets a little mascot that peeks out from behind the notch:
Clawd for Claude, the Codex pet (or any of your installed Codex pets) for Codex. They animate
while working, wave when they need you, and hop when they're done.

- **Answer from the notch.** Claude's questions and permission prompts drop down from the
  island, so you can reply without leaving what you're doing.
- **One click back.** Click a mascot to jump straight to its Ghostty tab or app.
- **Hover for detail.** Task, live action and 5-hour usage; ←/→ to flip between sessions.
- **Stays out of the way.** In full screen it hides with the menu bar and pops in for a moment
  when an agent finishes, so you can watch something while they work.

**Insanely light.** About 0.7% of one CPU core while an agent is working and its mascot is
animating, and around 42 MB of memory. It's native AppKit and Core Animation: no Electron, no
web view, no polling. Agents report in through hooks over a Unix socket, idle mascots settle so
nothing redraws when nothing is happening, and the window is only a notch tall.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/joey-david/topnotchers/master/install.sh | bash
```

or with Homebrew:

```sh
brew install joey-david/tap/topnotchers && topnotchers-setup
```

Needs an Apple silicon Mac on macOS 14 or later, notch or not, and the Xcode Command Line Tools
(`xcode-select --install`). Topnotchers builds on your machine, so there's no Gatekeeper
warning. Setup wires up the Claude Code and Codex hooks and starts the app at login (toggle it
from the menu-bar item).

Then approve the hooks once with `/hooks` in Codex, and let Topnotchers control Ghostty when
macOS asks (that's how a click focuses the right tab).

From a clone: `./install.sh` builds and installs, `./demo.sh` plays a tour with throwaway
sessions.

## Other agents

Up to 10, each on the left or right, set from the menu-bar item or
`~/.topnotchers/config.json`. Anything can report in:

```sh
~/.topnotchers/bin/topnotchers-hook --agent <id>                       # Claude-style hook JSON on stdin
~/.topnotchers/bin/topnotchers-hook emit --agent <id> --state working  # or question, done, end
```

---

Made by Joey. Follow [@t0rt0ised](https://x.com/t0rt0ised) for what's next, and if Topnotchers
saves you some tab-switching, a ⭐ helps other people find it.
