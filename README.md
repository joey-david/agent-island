# Topnotchers

A macOS app that shows your Claude Code and Codex sessions next to the notch.

![Topnotchers demo](docs/demo.gif)

Each session gets a small pet that animates while the agent works, shows an orange dot when it
asks you something, and a green one when it's done. Questions and permission prompts open under
the notch, so you can answer without finding the terminal. Clicking a pet focuses its Ghostty tab.

It's native AppKit and optimized to consume almost no resources (uses about 42 MB of memory at peak usage), with no measurable CPU when nothing is happening.

## Install

```sh
brew install joey-david/tap/topnotchers && topnotchers-setup
```

or `curl -fsSL https://raw.githubusercontent.com/joey-david/topnotchers/master/install.sh | bash`.
Needs Apple silicon, macOS 14+ and the Xcode Command Line Tools.

---

Made by Joey ([@t0rt0ised](https://x.com/t0rt0ised)).
