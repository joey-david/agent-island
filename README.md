# Agent Island

A Dynamic Island for coding agents on a notched Mac.

![Agent Island demo](docs/demo.gif)

One mascot per session peeks out from behind the notch: Clawd for Claude Code, the Codex pet
for Codex. They animate while working, wave when they need you, and jump when done.
Hover a side to see tasks, live actions and 5-hour usage (←/→ to switch sessions); click to
jump to the session. Claude's questions and permission prompts drop down from the island, so
you can answer without leaving what you're doing.

Native AppKit + Core Animation. No polling: agents report through hooks over a Unix socket.

## Install

```sh
./install.sh   # builds ~/Applications/Agent Island.app and wires Claude Code + Codex hooks
./demo.sh      # a scripted tour with throwaway sessions
```

Then approve the hooks once with `/hooks` in Codex, and let Agent Island control Ghostty when
macOS asks (to focus the right tab).

## Other agents

Up to 10, each on the left or right, set from the menu-bar item or
`~/.agent-island/config.json`. Anything can report in:

```sh
~/.agent-island/bin/island-hook --agent <id>                       # Claude-style hook JSON on stdin
~/.agent-island/bin/island-hook emit --agent <id> --state working  # or question, done, end
```
