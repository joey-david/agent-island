import AppKit
import QuartzCore

/// Demo mode's stand-in terminals: clicking a session opens a mock window for it, zooming out of
/// the island, so the recording can show "click the mascot, land in its chat". Each window replays
/// the actions its session reported and closes when the session exits.
final class StageTerminals {
    let layer = CALayer()
    private final class Term {
        let box = CALayer(), text = CATextLayer()
    }
    private var terms: [String: Term] = [:]
    private var history: [String: [String]] = [:]
    private var opened = 0, z: CGFloat = 0
    private let size = CGSize(width: 470, height: 196)
    var scale: CGFloat = 2

    /// Remembers what each session did, and redraws or closes open windows to match.
    func update(_ store: SessionStore, _ config: ConfigStore) {
        for s in store.sessions.values {
            guard let a = s.action, !a.isEmpty, history[s.key]?.last != a else { continue }
            history[s.key, default: []].append(a)
        }
        for (key, t) in terms {
            guard let s = store.sessions[key] else { close(key, t); continue }
            draw(t, s, config.agent(s.agent))
        }
    }

    func open(_ s: Session, agent: AgentConfig?, from p: CGPoint) {
        if let t = terms[s.key] { return raise(t) }
        let t = Term()
        terms[s.key] = t
        // Cascade: each new window a little lower and to the side of the last.
        let origins = [CGPoint(x: 410, y: 120), CGPoint(x: 150, y: 84), CGPoint(x: 280, y: 40)]
        let o = origins[opened % origins.count]
        opened += 1
        let frame = CGRect(origin: o, size: size)

        let box = t.box
        box.bounds = CGRect(origin: .zero, size: size)
        box.position = CGPoint(x: frame.midX, y: frame.midY)
        box.cornerRadius = 11
        box.cornerCurve = .continuous
        box.backgroundColor = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 0.97).cgColor
        box.borderWidth = 0.5
        box.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
        box.shadowColor = NSColor.black.cgColor
        box.shadowOpacity = 0.45
        box.shadowRadius = 22
        box.shadowOffset = CGSize(width: 0, height: -10)

        for (i, c) in ["#FF5F57", "#FEBC2E", "#28C840"].enumerated() {
            let d = CALayer()
            d.frame = CGRect(x: 14 + CGFloat(i) * 20, y: size.height - 21, width: 12, height: 12)
            d.cornerRadius = 6
            d.backgroundColor = NSColor(hex: c)?.cgColor
            box.addSublayer(d)
        }
        let title = CATextLayer()
        title.string = NSAttributedString(string: "\(s.project) — \(agent?.displayName ?? s.agent)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.62)])
        title.alignmentMode = .center
        title.frame = CGRect(x: 80, y: size.height - 24, width: size.width - 160, height: 16)
        title.contentsScale = scale
        box.addSublayer(title)
        let rule = CALayer()
        rule.frame = CGRect(x: 0, y: size.height - 33, width: size.width, height: 0.5)
        rule.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        box.addSublayer(rule)

        t.text.frame = CGRect(x: 18, y: 14, width: size.width - 36, height: size.height - 58)
        t.text.isWrapped = true
        t.text.contentsScale = scale
        box.addSublayer(t.text)
        draw(t, s, agent)
        layer.addSublayer(box)
        raise(t, pop: false)

        // Zoom out of the point that was clicked.
        let from = CGPoint(x: p.x, y: p.y), dur = 0.5
        let move = CASpringAnimation(keyPath: "position")
        move.fromValue = NSValue(point: from)
        move.toValue = NSValue(point: box.position)
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.06
        grow.toValue = 1
        for a in [move, grow] { a.damping = 22; a.stiffness = 260; a.mass = 1; a.duration = a.settlingDuration }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = dur * 0.4
        box.add(move, forKey: "open.move")
        box.add(grow, forKey: "open.grow")
        box.add(fade, forKey: "open.fade")
    }

    private func raise(_ t: Term, pop: Bool = true) {
        z += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        t.box.zPosition = z
        CATransaction.commit()
        guard pop else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.scale")
        a.values = [1, 1.025, 1]
        a.duration = 0.28
        t.box.add(a, forKey: "raise")
    }

    private func close(_ key: String, _ t: Term) {
        terms.removeValue(forKey: key)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { t.box.removeFromSuperlayer() }
        t.box.opacity = 0
        t.box.transform = CATransform3DMakeScale(0.96, 0.96, 1)
        CATransaction.commit()
    }

    private func draw(_ t: Term, _ s: Session, _ agent: AgentConfig?) {
        var acts = history[s.key] ?? []
        let current = s.state == .working ? acts.popLast() : nil
        let mono = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
        let dim = NSColor(white: 1, alpha: 0.45), white = NSColor(white: 1, alpha: 0.92)
        let tint = agent?.tint ?? .white
        let out = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        func line(_ s: String, _ c: NSColor, _ f: NSFont = mono) {
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: f, .foregroundColor: c, .paragraphStyle: para]))
        }
        line("~/projects/\(s.project)", dim)
        line("› " + (s.prompt ?? ""), white, bold)
        line("", dim)
        for a in acts.suffix(6) { line("● " + a, dim) }
        if let current { line("✻ " + current + "…", tint, bold) }
        if s.state == .done { line("✓ Done — ready for your next message", .systemGreen, bold) }
        t.text.string = out
    }
}

/// `--autoplay`: the demo, played inside the stage window. Sessions arrive through the same
/// socket protocol the hook speaks, and a drawn cursor hovers, types and clicks through the island,
/// so every run looks the same and the real pointer is never involved.
final class Autopilot {
    static let config = Config(agents: [
        AgentConfig(id: "claude", name: "Claude", side: .left, sprite: "clawd", color: "#D77757"),
        AgentConfig(id: "codex", name: "Codex", side: .right, sprite: "codex", color: "#9DB8FF"),
    ], doneLinger: 1200, menuBarIcon: false, launchAtLogin: false)

    private let store: SessionStore
    private let island: IslandController
    private let io = DispatchQueue(label: "island.autoplay")
    private let cursor = CALayer()
    private var at = CGPoint(x: 780, y: 110)
    private var hot: HoverButton?
    private var clients: [Int32] = []
    private var steps: [(delay: Double, run: (@escaping () -> Void) -> Void)] = []

    init(store: SessionStore, island: IslandController) {
        self.store = store
        self.island = island
        let img = NSCursor.arrow.image
        cursor.contents = img
        cursor.bounds = CGRect(origin: .zero, size: img.size)
        cursor.anchorPoint = CGPoint(x: NSCursor.arrow.hotSpot.x / img.size.width, y: 1 - NSCursor.arrow.hotSpot.y / img.size.height)
        cursor.position = at
        cursor.opacity = 0
        cursor.shadowColor = NSColor.black.cgColor
        cursor.shadowOpacity = 0.25
        cursor.shadowRadius = 2
        cursor.shadowOffset = CGSize(width: 0, height: -1)
        island.overlay(cursor)
    }

    // MARK: script

    func run() {
        let PA = "Build a notch monitor for coding agents", PB = "Tighten the landing page copy"
        let PC = "Profile the sync server", PX = "Fix the flaky sync test"
        let rest = CGPoint(x: 780, y: 110)

        wait(0.6) { self.cursor.opacity = 1 }
        emit(0.6, "claude", "a", "working", "agent-island", PA, "Reading Island.swift")
        emit(1.8, "codex", "x", "working", "earned-time", PX, "Running the server tests")
        emit(1.6, "claude", "a", "working", "agent-island", PA, "Editing Sprites.swift")
        // Hover: the side widens into a tray with the live action.
        move(0.4, toMascot: "claude")
        emit(1.2, "claude", "a", "working", "agent-island", PA, "Building the app")
        move(1.6, to: rest)
        // More sessions stack behind the first; the arrows flip through them.
        emit(0.5, "claude", "b", "working", "portfolio", PB, "Editing index.html")
        emit(0.8, "claude", "c", "idle", "sync-server", PC, nil)
        move(1.0, toMascot: "claude")
        key(1.0, 124); key(0.8, 124); key(0.8, 124); key(0.9, 53)
        move(0.3, to: rest)
        // A question expands the island into a panel; answer it.
        ask(0.8, "claude", "a", """
            {"hook_event_name":"PreToolUse","session_id":"a","cwd":"/Users/demo/projects/agent-island","tool_name":"AskUserQuestion",
             "tool_input":{"questions":[{"header":"Mascot","question":"Which mascot should sit on the right?","multiSelect":false,
             "options":[{"label":"Codex","description":"The official pet"},{"label":"Hoots","description":"The owl"},{"label":"Dewey","description":"The tidy one"}]}]}}
            """)
        move(1.1, toButton: "Hoots")
        click(0.5)
        emit(0.5, "claude", "a", "working", "agent-island", PA, "Applying your answer")
        move(0.2, to: rest)
        // A permission prompt; allow it.
        ask(1.0, "codex", "x", """
            {"hook_event_name":"PermissionRequest","session_id":"x","cwd":"/Users/demo/projects/earned-time","tool_name":"Bash",
             "tool_input":{"command":"npm publish --dry-run"}}
            """)
        move(1.1, toButton: "Allow")
        click(0.5)
        emit(0.3, "codex", "x", "working", "earned-time", PX, "Publishing a dry run")
        move(0.2, to: rest)
        // Codex finishes: hop, green dot. Click it to land in its terminal.
        emit(1.4, "codex", "x", "done", "earned-time", PX, nil)
        move(1.3, toMascot: "codex")
        click(1.0)
        move(0.8, to: CGPoint(x: 940, y: 60))
        // Claude too.
        emit(0.6, "claude", "b", "done", "portfolio", PB, nil)
        emit(1.0, "claude", "a", "done", "agent-island", PA, nil)
        move(1.2, toMascot: "claude")
        click(1.0)
        move(0.8, to: CGPoint(x: 940, y: 60))
        // Agents exit, windows close, the island tucks back behind the notch.
        end(1.6, "codex", "x"); end(0.9, "claude", "c"); end(0.8, "claude", "b"); end(0.8, "claude", "a")
        wait(2.0) { self.cursor.opacity = 0 }
        wait(0.6) {
            self.clients.forEach { close($0) }
            NSApp.terminate(nil)
        }
        next()
    }

    // MARK: steps

    private func step(_ delay: Double, _ run: @escaping (@escaping () -> Void) -> Void) { steps.append((delay, run)) }
    private func wait(_ d: Double, _ f: @escaping () -> Void) { step(d) { f(); $0() } }

    private func next() {
        guard !steps.isEmpty else { return }
        let s = steps.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + s.delay) { s.run { self.next() } }
    }

    private func emit(_ d: Double, _ agent: String, _ sid: String, _ state: String, _ project: String, _ prompt: String, _ action: String?) {
        var m: [String: Any] = ["event": "emit", "state": state, "cwd": "/Users/demo/projects/" + project, "prompt": prompt]
        m["action"] = action
        wait(d) { self.send(agent, sid, m) }
    }

    private func end(_ d: Double, _ agent: String, _ sid: String) {
        wait(d) { self.send(agent, sid, ["event": "SessionEnd"]) }
    }

    private func ask(_ d: Double, _ agent: String, _ sid: String, _ payload: String) {
        let p = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] ?? [:]
        wait(d) { self.send(agent, sid, ["payload": p, "wait": true]) }
    }

    private func key(_ d: Double, _ code: UInt16) { wait(d) { self.island.press(code) } }

    private func move(_ d: Double, toMascot agent: String) { move(d) { self.island.mascot(agent) } }
    private func move(_ d: Double, toButton title: String) { move(d) { self.island.button(title) } }
    private func move(_ d: Double, to p: CGPoint) { move(d) { p } }

    /// Glides the cursor to a target looked up when the move starts, easing in and out.
    private func move(_ d: Double, target: @escaping () -> CGPoint?) {
        step(d) { done in
            guard let to = target() else { return done() }
            let from = self.at, dur = 0.55 + min(0.35, hypot(to.x - from.x, to.y - from.y) / 2000)
            let start = CACurrentMediaTime()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: 1.0 / 60)
            timer.setEventHandler {
                let t = min(1, (CACurrentMediaTime() - start) / dur)
                let e = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                self.point(CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e))
                if t >= 1 { timer.cancel(); done() }
            }
            timer.resume()
        }
    }

    private func point(_ p: CGPoint) {
        at = p
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursor.position = p
        CATransaction.commit()
        island.fakePointer = p
        island.pointerMoved()
        let b = island.hitView(at: p).flatMap { v in sequence(first: v, next: \.superview).first { $0 is HoverButton } } as? HoverButton
        if b !== hot { hot?.highlight(false); b?.highlight(true); hot = b }
    }

    private func click(_ d: Double) {
        step(d) { done in
            let press = CABasicAnimation(keyPath: "transform.scale")
            press.fromValue = 1
            press.toValue = 0.82
            press.duration = 0.09
            press.autoreverses = true
            self.cursor.add(press, forKey: "press")
            self.island.send(.leftMouseDown, at: self.at)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                self.island.send(.leftMouseUp, at: self.at)
                done()
            }
        }
    }

    // MARK: transport

    /// One message over a socket pair into the same `Connection` the hook server uses.
    private func send(_ agent: String, _ sid: String, _ extra: [String: Any]) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { return }
        _ = fcntl(fds[0], F_SETFL, O_NONBLOCK)
        var m: [String: Any] = ["v": 1, "agent": agent, "session": sid, "pid": Int(getpid()), "wait": false, "payload": [String: Any]()]
        m.merge(extra) { $1 }
        if var p = m["payload"] as? [String: Any], !p.isEmpty { p["session_id"] = sid; m["payload"] = p }
        let store = self.store
        _ = Connection(fd: fds[0], queue: io) { msg, conn in store.handle(msg, conn: conn) }
        var data = (try? JSONSerialization.data(withJSONObject: m)) ?? Data()
        data.append(10)
        _ = data.withUnsafeBytes { write(fds[1], $0.baseAddress, $0.count) }
        clients.append(fds[1])
    }
}
