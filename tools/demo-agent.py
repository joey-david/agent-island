#!/usr/bin/env python3
"""A scripted stand-in for Claude Code or Codex, for recording the demo in real terminals.

It draws a session in the look of the real tool and reports through the real hook binary, so the
island sees exactly what it sees from the real agents: a session starting, prompts, tool calls,
a question or permission prompt answered from the notch, finishing, and exiting.

    demo-agent.py claude|codex SCENE

Steps marked `hold` wait for the recording driver to touch $DEMO_DIR/cue-<scene>-<name>, so it decides
when each beat happens.
"""
import itertools, json, os, subprocess, sys, time, uuid

KIND, SCENE = sys.argv[1], sys.argv[2]
HOOK = os.environ["DEMO_HOOK"]
CUES = os.environ["DEMO_DIR"]
SID = str(uuid.uuid4())
CWD = os.getcwd()
PROJECT = os.path.basename(CWD)

DIM, BOLD, RESET = "\033[2m", "\033[1m", "\033[0m"
ORANGE, GREEN, BLUE, GREY = "\033[38;5;173m", "\033[38;5;71m", "\033[38;5;111m", "\033[38;5;245m"
ACCENT = ORANGE if KIND == "claude" else BLUE


def out(s=""):
    sys.stdout.write(s + "\n")
    sys.stdout.flush()


def title(t):
    sys.stdout.write(f"\033]0;{t}\007")
    sys.stdout.flush()


def hook(event, wait=False, **fields):
    payload = {"hook_event_name": event, "session_id": SID, "cwd": CWD, **fields}
    args = [HOOK, "--agent", KIND] + (["--wait"] if wait else [])
    r = subprocess.run(args, input=json.dumps(payload), capture_output=True, text=True)
    return r.stdout


def spin(label, seconds):
    frames = "·✢✳✶✻✽✻✶✳✢" if KIND == "claude" else "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    end = time.time() + seconds
    for f in itertools.cycle(frames):
        if time.time() >= end:
            break
        sys.stdout.write(f"\r{ACCENT}{f}{RESET} {label}{DIM}…{RESET}  ")
        sys.stdout.flush()
        time.sleep(0.12)
    sys.stdout.write("\r\033[2K")
    sys.stdout.flush()


def hold(name):
    path = os.path.join(CUES, f"cue-{SCENE}-{name}")
    while not os.path.exists(path):
        spin("Thinking" if KIND == "claude" else "Working", 0.5)


def tool(name, inp, label, result, seconds):
    hook("PreToolUse", tool_name=name, tool_input=inp)
    spin(label, seconds)
    if KIND == "claude":
        arg = inp.get("file_path", inp.get("command", ""))
        out(f"{ACCENT}⏺{RESET} {BOLD}{name}{RESET}({arg})")
        out(f"  {GREY}⎿  {result}{RESET}")
    else:
        out(f"{GREY}•{RESET} {BOLD}{label}{RESET}")
        out(f"  {GREY}└ {result}{RESET}")
    hook("PostToolUse", tool_name=name, tool_input=inp)


def header():
    os.system("clear")
    home = f"~/projects/{PROJECT}"
    if KIND == "claude":
        out(f"{ACCENT}╭───────────────────────────────────────────╮{RESET}")
        out(f"{ACCENT}│{RESET} {ACCENT}✻{RESET} Welcome to {BOLD}Claude Code{RESET}                    {ACCENT}│{RESET}")
        out(f"{ACCENT}│{RESET}   {GREY}cwd: {home:<34}{RESET}{ACCENT}│{RESET}")
        out(f"{ACCENT}╰───────────────────────────────────────────╯{RESET}")
    else:
        out(f"{GREY}╭──────────────────────────────────────────╮{RESET}")
        out(f"{GREY}│{RESET} {BOLD}>_ OpenAI Codex{RESET} {GREY}(v0.163.0){RESET}                 {GREY}│{RESET}")
        out(f"{GREY}│{RESET}                                          {GREY}│{RESET}")
        out(f"{GREY}│{RESET} {GREY}model:{RESET}     gpt-6.1                       {GREY}│{RESET}")
        out(f"{GREY}│{RESET} {GREY}directory:{RESET} {home:<30}{GREY}│{RESET}")
        out(f"{GREY}╰──────────────────────────────────────────╯{RESET}")
    out()


def prompt():
    sys.stdout.write(f"{BOLD}{'>' if KIND == 'claude' else '›'}{RESET} ")
    sys.stdout.flush()
    line = sys.stdin.readline()
    if not line:
        return None
    return line.strip()


def finish(summary, seconds):
    hook("Stop")
    title(("✳ " if KIND == "claude" else "") + PROJECT)
    if KIND == "claude":
        out(f"{ACCENT}⏺{RESET} {summary}")
        out(f"{GREY}✻ Worked for {seconds}s{RESET}")
    else:
        out(f"{GREY}─ Worked for {seconds}s ─────────────────────────{RESET}")
        out(summary)
    out()


def ask_mascot():
    q = {"questions": [{"header": "Mascot", "question": "Which mascot should sit on the right?", "multiSelect": False,
                        "options": [{"label": "Codex", "description": "The official pet"},
                                    {"label": "Hoots", "description": "The owl"},
                                    {"label": "Dewey", "description": "The tidy one"}]}]}
    out(f"{ACCENT}⏺{RESET} {BOLD}AskUserQuestion{RESET}")
    out(f"  {GREY}⎿  Which mascot should sit on the right?{RESET}")
    reply = hook("PreToolUse", wait=True, tool_name="AskUserQuestion", tool_input=q)
    try:
        answers = json.loads(reply)["hookSpecificOutput"]["updatedInput"]["answers"]
        choice = next(iter(answers.values()))
    except Exception:
        choice = "Hoots"
    out(f"  {GREEN}⎿  You answered from the notch: {choice}{RESET}")
    return choice


def allow_publish():
    out(f"{ORANGE}▲{RESET} {BOLD}Allow command?{RESET} npm publish --dry-run")
    reply = hook("PermissionRequest", wait=True, tool_name="Bash", tool_input={"command": "npm publish --dry-run"})
    ok = '"allow"' in reply or not reply
    out(f"  {GREEN if ok else ORANGE}└ {'Approved from the notch' if ok else 'Denied'}{RESET}")


def scene(task):
    title(("✳ " if KIND == "claude" else "") + task)
    if SCENE == "notch":
        tool("Read", {"file_path": "Sources/App/Island.swift"}, "Reading Island.swift", "Read 912 lines", 0.7)
        tool("Edit", {"file_path": "Sources/App/Sprites.swift"}, "Editing Sprites.swift", "Updated with 12 additions and 3 removals", 0.9)
        tool("Bash", {"command": "./build.sh", "description": "Building the app"}, "Building the app", "Build succeeded", 0.8)
        hold("ask")
        choice = ask_mascot()
        tool("Edit", {"file_path": "Sources/App/Config.swift", "description": "Applying your answer"}, "Applying your answer", "Updated with 1 addition and 1 removal", 0.8)
        hold("done")
        finish(f"Done. {choice} now sits on the right, and the app builds and runs.", 74)
    elif SCENE == "landing":
        tool("Read", {"file_path": "site/index.html"}, "Reading index.html", "Read 214 lines", 0.7)
        tool("Edit", {"file_path": "site/index.html"}, "Editing index.html", "Updated with 9 additions and 14 removals", 0.9)
        hold("done")
        finish("Tightened the hero and pricing copy; the page is 30% shorter.", 41)
    elif SCENE == "sync":
        tool("Bash", {"command": "npm test", "description": "Running the server tests"}, "Running the server tests", "41 passed, 1 failed (sync.test.ts)", 0.8)
        tool("Edit", {"file_path": "src/sync.ts"}, "Edited src/sync.ts (+6 -2)", "Awaits the flush before closing the socket", 0.7)
        tool("Bash", {"command": "npm test", "description": "Running the server tests"}, "Running the server tests", "42 passed", 0.6)
        hold("perm")
        allow_publish()
        tool("Bash", {"command": "npm publish --dry-run", "description": "Publishing a dry run"}, "Publishing a dry run", "earned-time@2.4.1 would be published", 0.7)
        hold("done")
        finish("The flaky sync test is fixed: the socket closed before the last flush. All 42 tests pass.", 63)


header()
hook("SessionStart", source="startup")
while True:
    p = prompt()
    if p is None or p in ("/exit", "exit", "/quit"):
        hook("SessionEnd", reason="prompt_input_exit")
        break
    if not p:
        continue
    hook("UserPromptSubmit", prompt=p)
    out()
    scene(p)
