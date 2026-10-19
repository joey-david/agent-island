import AppKit

/// Bringing a session's chat to the front: its Ghostty terminal, or the app it runs in.
enum Focus {
    static let ghostty = "com.mitchellh.ghostty"
    private static let queue = DispatchQueue(label: "island.applescript")

    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil ? r : nil
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path
    }

    private static var ghosttyFront: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ghostty }

    private static func focusedTerminal(_ done: @escaping (_ id: String?, _ cwd: String?) -> Void) {
        queue.async {
            let r = run("tell application \"Ghostty\" to get {id, working directory} of focused terminal of selected tab of front window")
            let id = r?.atIndex(1)?.stringValue, wd = r?.atIndex(2)?.stringValue
            DispatchQueue.main.async { done(id, wd) }
        }
    }

    /// The prompt was just typed, so Ghostty's focused terminal is almost surely this session's.
    static func captureTerminal(_ s: Session) {
        guard s.inGhostty, ghosttyFront else { return }
        let cwd = s.cwd
        focusedTerminal { id, wd in
            guard let id else { return }
            if s.terminalID == nil || same(wd, cwd) { s.terminalID = id }
        }
    }

    static func isFocused(_ s: Session, _ done: @escaping (Bool) -> Void) {
        guard s.inGhostty, ghosttyFront, let mine = s.terminalID else { return done(false) }
        focusedTerminal { id, _ in done(id == mine) }
    }

    /// Titles of every Ghostty terminal by id; Claude Code keeps its task summary there.
    static func titles(_ done: @escaping ([(id: String, name: String, cwd: String)]) -> Void) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: ghostty).first != nil else { return done([]) }
        queue.async {
            var out: [(id: String, name: String, cwd: String)] = []
            if let r = run("tell application \"Ghostty\" to get {id, name, working directory} of terminals"),
               let ids = r.atIndex(1), let names = r.atIndex(2), let dirs = r.atIndex(3), ids.numberOfItems > 0,
               names.numberOfItems == ids.numberOfItems, dirs.numberOfItems == ids.numberOfItems {
                for i in 1...ids.numberOfItems {
                    out.append((ids.atIndex(i)?.stringValue ?? "", names.atIndex(i)?.stringValue ?? "", dirs.atIndex(i)?.stringValue ?? ""))
                }
            }
            DispatchQueue.main.async { done(out) }
        }
    }

    static func open(_ s: Session, agent: AgentConfig?) {
        if s.inGhostty {
            let id = s.terminalID, cwd = s.cwd
            queue.async {
                var ok = false
                if let id { ok = run("tell application \"Ghostty\"\nfocus terminal id \"\(esc(id))\"\nactivate\nend tell") != nil }
                if !ok, let cwd {
                    ok = run("tell application \"Ghostty\"\nfocus (first terminal whose working directory is \"\(esc(cwd))\")\nactivate\nend tell") != nil
                }
                if !ok { DispatchQueue.main.async { activate(ghostty) } }
            }
            return
        }
        if s.term == nil, let t = agent?.url,
           let url = URL(string: t.replacingOccurrences(of: "{session}", with: s.id)
               .replacingOccurrences(of: "{cwd}", with: s.cwd?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")) {
            NSWorkspace.shared.open(url)
            return
        }
        if let b = s.bundle ?? agent?.app { activate(b) }
    }

    static func activate(_ bundle: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
