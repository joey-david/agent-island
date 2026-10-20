#!/usr/bin/env python3
"""Records docs/demo.mp4 + docs/demo.gif on the real screen and notch.

Real Ghostty windows run scripted stand-ins for Claude Code and Codex (tools/demo-agent.py) that
report through the real hooks to a separate Topnotchers instance with its own home, so your own
sessions stay out of the frame. Each beat waits on the app's actual state, and clicks land where
the app says its mascots and buttons are.

While it runs (about a minute) it takes over the pointer, quits your Topnotchers, minimizes your
Ghostty windows, covers the desktop with a wallpaper and opens a Safari page. All of
that is put back afterwards.
Needs screen-recording and accessibility permission for the terminal, and ffmpeg.
"""
import json, os, shutil, socket, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "build")
D = os.path.join(B, "demo")
HOME = os.path.join(D, "home")
CUES = os.path.join(D, "cues")
DIRECTOR = os.path.join(B, "director")
APP = os.path.join(B, "Topnotchers.app/Contents/MacOS/Topnotchers")
REAL = os.path.expanduser("~/.topnotchers")
WALLPAPER = "/System/Library/Desktop Pictures/Sonoma.heic"
RAW = os.path.join(B, "raw.mov")
# The hardware notch in points: left, right, screen width, height (the island's, a point past the
# safe area).
NOTCH = (645.5, 824.5, 1470, 33)


def run(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k).stdout.strip()


def osa(script):
    return run("osascript", "-e", script)


# MARK: setup

def prepare():
    run(os.path.join(ROOT, "build.sh"))
    run("swiftc", "-O", os.path.join(ROOT, "tools/director.swift"), "-o", DIRECTOR)
    shutil.rmtree(D, ignore_errors=True)
    for d in [HOME, CUES, os.path.join(D, "bin"), os.path.join(D, "zdot")]:
        os.makedirs(d)
    open(os.path.join(HOME, "events.log"), "w").close()   # the app logs events while this exists
    for p in ["topnotchers", "portfolio", "earned-time"]:
        os.makedirs(os.path.join(D, "projects", p))
    for sub in ["sprites", "usage"]:
        if os.path.isdir(os.path.join(REAL, sub)):
            shutil.copytree(os.path.join(REAL, sub), os.path.join(HOME, sub))
    json.dump({"agents": [
        {"id": "claude", "name": "Claude", "side": "left", "sprite": "clawd", "color": "#D77757"},
        {"id": "codex", "name": "Codex", "side": "right", "sprite": "codex", "color": "#9DB8FF"},
    ], "doneLinger": 1200, "menuBarIcon": False, "launchAtLogin": False}, open(os.path.join(HOME, "config.json"), "w"))
    agent = os.path.join(ROOT, "tools/demo-agent.py")
    for kind in ["claude", "codex"]:
        p = os.path.join(D, "bin", kind)
        open(p, "w").write(f'#!/bin/bash\nexec python3 -I "{agent}" {kind} "$DEMO_SCENE"\n')
        os.chmod(p, 0o755)
    open(os.path.join(D, "zdot", ".zshrc"), "w").write(
        f'export PATH="{D}/bin:$PATH"\nPS1="%F{{245}}%1~%f %F{{76}}❯%f "\n'
        'precmd() { print -n "\\e]0;demo-$DEMO_SCENE\\a\\e]7;file://$HOST$PWD\\a" }\nprecmd\nclear\n')


# MARK: windows

def window(scene, project, x, y, w=660, h=380):
    """Opens a demo terminal at its final size and place with its shell up, then parks it minimized
    (macOS won't let a window sit fully off-screen); `show` brings it back."""
    env = [f"ZDOTDIR={D}/zdot", f"DEMO_SCENE={scene}", f"DEMO_DIR={CUES}", f"DEMO_HOOK={B}/topnotchers-hook",
           f"TOPNOTCHERS_HOME={HOME}"]
    ids = osa(f'''
        tell application "Ghostty"
          set cfg to new surface configuration
          set initial working directory of cfg to "{D}/projects/{project}"
          set command of cfg to "/bin/zsh -i"
          set environment variables of cfg to {{{", ".join(json.dumps(e) for e in env)}}}
          set font size of cfg to 13
          set w to new window with configuration cfg
          set r to (id of w) & "|" & (id of focused terminal of selected tab of w)
        end tell
        return r''')
    wid, tid = ids.split("|")
    time.sleep(0.6)   # let the shell clear its login banner before parking
    # Resize the new window by its title, which the demo shell sets to its scene: the window
    # System Events calls frontmost isn't reliably the one just opened.
    name = "demo-" + scene
    for _ in range(40):
        try:
            osa(f'''tell application "System Events" to tell process "Ghostty"
              set win to first window whose name is "{name}"
              set size of win to {{{w}, {h}}}
              set position of win to {{{x}, {y}}}
            end tell''')
            break
        except subprocess.CalledProcessError:
            time.sleep(0.05)
    minimized(name, True)
    return {"window": wid, "term": tid, "center": (x + w / 2, y + h / 2), "name": name}


def minimized(name, on):
    osa(f'''tell application "System Events" to tell process "Ghostty"
      set value of attribute "AXMinimized" of (first window whose name is "{name}") to {"true" if on else "false"}
    end tell''')


def show(t):
    minimized(t["name"], False)
    time.sleep(0.35)
    focus(t)


def term(t):
    return f'(first terminal whose id is "{t["term"]}")'


def type_in(t, text, gap=0.035):
    """Types one character at a time, like a quick typist, then presses Return."""
    osa(f'''tell application "Ghostty"
      set t to {term(t)}
      repeat with c in characters of {json.dumps(text)}
        input text (contents of c) to t
        delay {gap}
      end repeat
      delay 0.15
      send key "enter" to t
    end tell''')


def focus(t):
    osa(f'tell application "Ghostty" to focus {term(t)}')


def minimize_ghostty():
    """Minimizes the Ghostty windows that are open now and returns their titles."""
    titles = osa('''
        set out to {}
        tell application "System Events" to tell process "Ghostty"
          repeat with w in windows
            if value of attribute "AXMinimized" of w is false then
              set end of out to name of w
              set value of attribute "AXMinimized" of w to true
            end if
          end repeat
        end tell
        set AppleScript's text item delimiters to linefeed
        return out as text''')
    return [t for t in titles.split("\n") if t]


def restore_ghostty(titles):
    """Unminimizes what minimize_ghostty hid. Titles change while minimized (agents set them), so
    when some no longer match, it brings back every minimized Ghostty window."""
    back = 0
    for t in titles:
        try:
            osa(f'''tell application "System Events" to tell process "Ghostty"
              set value of attribute "AXMinimized" of (first window whose name is {json.dumps(t)}) to false
            end tell''')
            back += 1
        except subprocess.CalledProcessError:
            pass
    if back < len(titles):
        osa('''tell application "System Events" to tell process "Ghostty"
          repeat with w in windows
            set value of attribute "AXMinimized" of w to false
          end repeat
        end tell''')


# MARK: the app

def ask(what):
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.path.join(HOME, "topnotchers.sock"))
    s.sendall((json.dumps({"event": "where", "what": what, "wait": True}) + "\n").encode())
    data = b""
    while chunk := s.recv(65536):
        data += chunk
    return json.loads(data or b"{}")


def until(cond, what, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if cond(ask("state")):
                return
        except OSError:
            pass
        time.sleep(0.1)
    names = osa('tell application "Ghostty" to get name of every terminal')
    raise SystemExit(f"timed out waiting for {what} (terminals: {names})")


def sessions(st, agent, state=None):
    return [s for s in st["sessions"] if s["agent"] == agent and (state is None or s["state"] == state)]


def point(what, timeout=5):
    """Where the app draws `what`, once it's on screen."""
    end = time.time() + timeout
    while time.time() < end:
        p = ask(what)
        if "x" in p:
            return p["x"], p["y"]
        time.sleep(0.1)
    raise SystemExit(f"nothing at {what}")


PAGE = "https://en.wikipedia.org/wiki/Tortoise"


def desktop_page(w, h):
    """Opens the page filling the desktop under the menu bar (not full screen, so it stays on this
    space and the menu bar and island stay up)."""
    osa(f'tell application "Safari"\nmake new document with properties {{URL:"{PAGE}"}}\nactivate\nend tell')
    time.sleep(1.0)
    osa(f'tell application "Safari" to set bounds of front window to {{0, 0, {w}, {h}}}')


def close_page():
    try:
        osa(f'tell application "Safari" to close (every document whose URL is "{PAGE}")')
    except subprocess.CalledProcessError:
        pass


def glide(x, y, ms=None):
    run(DIRECTOR, "glide", str(x), str(y), *([str(ms)] if ms else []))


def click(x, y):
    glide(x, y)
    time.sleep(0.25)
    run(DIRECTOR, "click", str(x), str(y))


# Stretches of the recording to zoom in on the notch, in video seconds.
T0 = 0.0
TRIM = 1.0
MARKS = []
# Moments a mascot pops out: (video seconds, agent), each drawn as a soft glow around the island.
GLOWS = []
TINTS = {"claude": "D97757", "codex": "4C8DFF"}


def now():
    return time.time() - T0 - TRIM


def zoom_in():
    MARKS.append([now(), None])


def zoom_out(after=0.0):
    time.sleep(after)
    MARKS[-1][1] = now()


def zoom_filter(z=1.35, ease=0.7):
    """zoompan expression: a smoothstep ramp into each marked stretch and back out, toward the top
    middle of the screen where the notch is."""
    parts = []
    for a, b in MARKS:
        up = f"clip((in_time-{a - ease:.2f})/{ease},0,1)"
        down = f"clip(({b + ease:.2f}-in_time)/{ease},0,1)"
        parts.append(f"min({up},{down})")
    e = "0"
    for p in parts:
        e = f"max({e},{p})"
    smooth = f"({e})*({e})*(3-2*({e}))"
    return f"zoompan=z='1+{z - 1}*{smooth}':x='(iw-iw/zoom)/2':y='0':d=1:fps=30:s=1440x936"


def cue(scene, name):
    open(os.path.join(CUES, f"cue-{scene}-{name}"), "w").close()


# MARK: the story

def stage():
    """The three terminals, made before recording starts."""
    return (window("notch", "topnotchers", 50, 80), window("sync", "earned-time", 760, 190),
            window("landing", "portfolio", 300, 470))


def story(a, x, b):
    rest = (735, 800)
    glide(*rest, 300)
    time.sleep(0.8)

    # A terminal opens and Claude starts: the island notices and Clawd pops out.
    show(a)
    type_in(a, "claude")
    until(lambda st: sessions(st, "claude"), "claude to start")
    GLOWS.append((now() + 0.3, "claude"))
    time.sleep(0.5)
    type_in(a, "Let me pick the mascots")
    time.sleep(0.5)

    # Codex starts in another window and shows up on the right.
    show(x)
    type_in(x, "codex")
    until(lambda st: sessions(st, "codex"), "codex to start")
    GLOWS.append((now() + 0.3, "codex"))
    time.sleep(0.5)
    type_in(x, "Fix the flaky sync test")
    time.sleep(0.5)

    # A second Claude session: it stacks up behind the first.
    show(b)
    type_in(b, "claude")
    until(lambda st: len(sessions(st, "claude")) == 2, "the second claude")
    time.sleep(0.5)
    type_in(b, "Tighten the landing copy")
    time.sleep(0.8)

    # Go do something else. The agents stay in view at the top of the screen.
    desktop_page(*SCREEN)
    time.sleep(2.2)

    # Hover a side for the details; hover its dots to flip between that agent's sessions.
    zoom_in()
    glide(*point("mascot:claude"), 800)
    time.sleep(2.0)
    glide(*point("pip:claude:1"), 500)
    time.sleep(1.8)
    glide(*point("pip:claude:0"), 400)
    time.sleep(1.6)
    glide(*point("mascot:codex"), 900)
    time.sleep(2.2)
    zoom_out()
    glide(*rest, 600)
    time.sleep(0.8)
    # Meanwhile, reading.
    run(DIRECTOR, "scroll", "520", "1100")
    time.sleep(1.6)

    # Claude has a question: it drops down over the page. Read it, answer it, carry on.
    cue("notch", "ask")
    until(lambda st: st["pending"] == 1, "the question")
    zoom_in()
    time.sleep(3.2)
    hx, hy = point("button:Hoots")
    glide(hx, hy, 800)
    time.sleep(0.6)
    run(DIRECTOR, "click", str(hx), str(hy))
    until(lambda st: st["pending"] == 0, "the answer")
    zoom_out(0.4)
    glide(*rest, 600)
    time.sleep(1.8)

    # Codex wants permission to run a command: allow it the same way.
    cue("sync", "perm")
    until(lambda st: st["pending"] == 1, "the permission prompt")
    zoom_in()
    time.sleep(3.0)
    ax, ay = point("button:Allow")
    glide(ax, ay, 800)
    time.sleep(0.6)
    run(DIRECTOR, "click", str(ax), str(ay))
    until(lambda st: st["pending"] == 0, "the approval")
    zoom_out(0.4)
    glide(*rest, 600)
    time.sleep(2.0)

    # Codex finishes: a hop and a green dot.
    cue("sync", "done")
    until(lambda st: sessions(st, "codex", "done"), "codex to finish")
    zoom_in()
    time.sleep(2.6)

    # Both Claude sessions finish. One click on Clawd: straight back to the latest one's terminal.
    cue("landing", "done")
    time.sleep(1.0)
    cue("notch", "done")
    until(lambda st: len(sessions(st, "claude", "done")) == 2, "claude to finish")
    time.sleep(1.4)
    click(*point("mascot:claude"))
    zoom_out(0.3)
    glide(*rest, 600)
    time.sleep(2.4)

    # And Codex's window is one click away.
    click(*point("mascot:codex"))
    time.sleep(0.4)
    glide(*rest, 500)
    time.sleep(2.0)

    # Agents exit (killed, as closing the tab would) and the island tucks back behind the notch.
    for kind, scene in [("codex", "sync"), ("claude", "landing"), ("claude", "notch")]:
        subprocess.run(["pkill", "-9", "-f", f"demo-agent.py {kind} {scene}"])
        time.sleep(0.45)
    until(lambda st: not st["sessions"], "every agent to exit")
    time.sleep(1.8)


# MARK: run

SCREEN = (0, 0)


def main():
    global SCREEN
    prepare()
    W, H = (int(float(v)) for v in osa('tell application "Finder" to get bounds of window of desktop').split(", ")[2:])
    SCREEN = (W, H)
    run("pkill", "-x", "Topnotchers") if subprocess.run(["pgrep", "-x", "Topnotchers"], capture_output=True).returncode == 0 else None
    backdrop = subprocess.Popen([DIRECTOR, "backdrop", WALLPAPER])
    hidden = minimize_ghostty()
    app = subprocess.Popen([APP], env={**os.environ, "TOPNOTCHERS_HOME": HOME}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    demo = list(stage())
    time.sleep(1.5)
    raw = RAW
    if os.path.exists(raw):
        os.remove(raw)
    global T0
    t0 = T0 = time.time()
    cap = subprocess.Popen(["screencapture", "-v", "-V", "120", f"-R0,0,{W},{H}", raw], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = None
    try:
        time.sleep(0.8)
        story(*demo)
        end = time.time() - t0
    finally:
        for t in demo:
            try:
                osa(f'tell application "Ghostty" to close window (first window whose id is "{t["window"]}")')
            except subprocess.CalledProcessError:
                pass
        close_page()
        app.terminate()
        backdrop.terminate()
        restore_ghostty(hidden)
        if cap.poll() is None and end is None:
            cap.terminate()
        subprocess.run(["open", os.path.expanduser("~/Applications/Topnotchers.app")])
    print("demo ran for %.1fs; waiting for screencapture to finish" % end)
    cap.wait()
    json.dump({"end": end, "zoom": MARKS, "glow": GLOWS}, open(os.path.join(D, "marks.json"), "w"))
    encode()


def island_edges(t):
    """Left and right edge of the island near the notch, in points, at video second t."""
    row = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", "%.2f" % (t + TRIM), "-i", RAW, "-vf",
                          f"crop=1400:1:{NOTCH[0] * 2 - 500:.0f}:30,format=gray", "-frames:v", "1", "-f", "rawvideo", "-"],
                         check=True, capture_output=True).stdout
    dark = [i for i, v in enumerate(row) if v < 8]
    x0 = NOTCH[0] * 2 - 500
    return (dark[0] + x0) / 2, (dark[-1] + 1 + x0) / 2


def encode():
    """docs/demo.mp4 and .gif from the raw capture and build/demo/marks.json."""
    m = json.load(open(os.path.join(D, "marks.json")))
    MARKS[:] = m["zoom"]
    out = os.path.join(ROOT, "docs")
    W, nh = NOTCH[2], NOTCH[3]
    # The recording can't see the hardware notch, so draw it in: without it the island reads as
    # a black bar for no reason. A pulse of glow around the island marks each mascot popping out.
    notch = os.path.join(D, "notch.png")
    run(DIRECTOR, "notch", notch, str(W), "80", "2", str(NOTCH[0]), str(NOTCH[1]), str(nh))
    inputs, graph, last = ["-i", notch], [], "v"
    for k, (t, agent) in enumerate(m["glow"]):
        png = os.path.join(D, f"glow{k}.png")
        run(DIRECTOR, "notch", png, str(W), "80", "2", *map(str, island_edges(t + 0.6)), str(nh), TINTS[agent])
        inputs += ["-framerate", "30", "-loop", "1", "-t", "1.6", "-i", png]
        graph.append(f"[{k + 2}]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*pow(sin(PI*T/0.8),2)',"
                     f"setpts=PTS-STARTPTS+{t:.2f}/TB[g{k}];[{last}][g{k}]overlay=eof_action=pass:enable='between(t,{t:.2f},{t + 1.6:.2f})'[o{k}]")
        last = f"o{k}"
    graph = [f"[0]fps=30,setpts=PTS-STARTPTS[v]"] + graph + [f"[{last}][1]overlay,{zoom_filter()}"]
    trim = ["-ss", str(TRIM), "-to", "%.2f" % (m["end"] - 0.3), "-i", RAW]
    mp4, gif = os.path.join(out, "demo.mp4"), os.path.join(out, "demo.gif")
    # Zoom from the full-resolution capture, so zoomed stretches stay sharp at 1440 wide.
    run("ffmpeg", "-loglevel", "error", "-y", *trim, *inputs, "-filter_complex", ";".join(graph), "-c:v", "libx264",
        "-pix_fmt", "yuv420p", "-crf", "22", "-preset", "slow", "-movflags", "+faststart", "-an", mp4)
    run("ffmpeg", "-loglevel", "error", "-y", "-i", mp4, "-vf", "fps=10,scale=800:-1:flags=lanczos,split[a][b];"
        "[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle", gif)
    # GitHub won't show a README image over 10 MB.
    if os.path.getsize(gif) > 10_000_000 and shutil.which("gifsicle"):
        run("gifsicle", "-O3", "--lossy=100", gif, "-o", gif)
    print(run("ls", "-la", out))

if __name__ == "__main__":
    encode() if sys.argv[1:] == ["--encode"] else main()
