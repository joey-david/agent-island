import AppKit

enum AgentState: Int, Codable, Comparable {
    case idle, done, working, question
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

final class Session: Codable {
    let agent: String
    let id: String
    var pid: Int32
    var cwd: String?
    var tty: String?
    var term: String?
    var bundle: String?
    var state = AgentState.idle
    var seen = true
    var updated = Date()
    var terminalID: String?
    /// What it was asked to do, what it last did, and the terminal's title for the task.
    var prompt: String?
    var action: String?
    var title: String?

    init(agent: String, id: String, pid: Int32) { self.agent = agent; self.id = id; self.pid = pid }
    var key: String { agent + "/" + id }
    var project: String { cwd.map { ($0 as NSString).lastPathComponent } ?? String(id.prefix(8)) }
    var inGhostty: Bool { term == "ghostty" || bundle == Focus.ghostty }
}

struct Question {
    let header: String
    let text: String
    let options: [(label: String, detail: String)]
    let multi: Bool
}

final class Pending {
    enum Kind {
        case ask([Question], input: [String: Any])
        case permission(tool: String, summary: String)
    }
    let session: Session
    let kind: Kind
    let conn: Connection
    init(session: Session, kind: Kind, conn: Connection) { self.session = session; self.kind = kind; self.conn = conn }

    func output(answers: [String: String]) -> String {
        guard case .ask(_, var input) = kind else { return "" }
        input["answers"] = answers
        return json(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input]])
    }

    func output(allow: Bool) -> String {
        let decision: [String: Any] = allow ? ["behavior": "allow"] : ["behavior": "deny", "message": "Denied from Agent Island."]
        return json(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
    }

    private func json(_ o: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

struct AgentSummary {
    let state: AgentState
    let count: Int
}

final class SessionStore {
    private(set) var sessions: [String: Session] = [:]
    private(set) var pending: [Pending] = []
    var onChange: (() -> Void)?
    private let config: ConfigStore
    private var exits: [Int32: DispatchSourceProcess] = [:]
    private var saveQueued = false
    private var lingerToken = 0
    private static let url = islandHome.appendingPathComponent("sessions.json")

    init(config: ConfigStore) {
        self.config = config
        restore()
    }

    // MARK: events

    func handle(_ msg: [String: Any], conn: Connection) {
        let agent = msg["agent"] as? String ?? "agent"
        guard config.ensure(agent) != nil else { return conn.respond("") }
        let p = msg["payload"] as? [String: Any] ?? [:]
        let event = p["hook_event_name"] as? String ?? msg["event"] as? String ?? ""
        let pid = Int32(msg["pid"] as? Int ?? 0)
        let sid = p["session_id"] as? String ?? msg["session"] as? String ?? "pid\(pid)"
        let key = agent + "/" + sid
        let emitted = msg["state"] as? String
        Self.debug("\(agent) \(event) \(sid) wait=\(msg["wait"] as? Bool ?? false) term=\(msg["term"] as? String ?? "-") bundle=\(msg["bundle"] as? String ?? "-")")

        if event == "SessionEnd" || emitted == "end" {
            remove(key)
            conn.respond("")
            return changed()
        }

        let s = sessions[key] ?? Session(agent: agent, id: sid, pid: pid)
        sessions[key] = s
        if pid > 1 { s.pid = pid; watchExit(pid) }
        s.cwd = p["cwd"] as? String ?? msg["cwd"] as? String ?? s.cwd
        s.tty = msg["tty"] as? String ?? s.tty
        s.term = msg["term"] as? String ?? s.term
        s.bundle = msg["bundle"] as? String ?? s.bundle
        s.updated = Date()

        var made: Pending?
        let wait = msg["wait"] as? Bool ?? false
        switch event {
        case "SessionStart":
            Focus.captureTerminal(s)
        case "UserPromptSubmit":
            s.state = .working
            s.seen = true
            s.action = nil
            if let text = p["prompt"] as? String { s.prompt = Self.firstLine(text) }
            Focus.captureTerminal(s)
        case "Notification":
            let type = p["notification_type"] as? String ?? ""
            if type == "permission_prompt" || type == "elicitation_dialog" { s.state = .question }
        case "PermissionRequest":
            s.state = .question
            if wait {
                made = Pending(session: s, kind: .permission(tool: p["tool_name"] as? String ?? "tool",
                                                             summary: Self.summarize(p["tool_input"])), conn: conn)
            }
        case "PreToolUse" where wait && p["tool_name"] as? String == "AskUserQuestion":
            if let input = p["tool_input"] as? [String: Any], let qs = Self.questions(input) {
                s.state = .question
                made = Pending(session: s, kind: .ask(qs, input: input), conn: conn)
            }
        case "Stop", "Interrupt":
            s.state = .done
            s.seen = false
        case "emit":
            switch emitted {
            case "working": s.state = .working
            case "question": s.state = .question
            case "done": s.state = .done; s.seen = false
            default: s.state = .idle
            }
        default: // PostToolUse, SubagentStart, PreCompact, ...
            if let tool = p["tool_name"] as? String { s.action = Self.describe(tool, p["tool_input"]) }
            if !pending.contains(where: { $0.session === s }) { s.state = .working }
        }

        if let made {
            pending.append(made)
            conn.onHangup = { [weak self, weak made] in
                guard let self, let made, let i = self.pending.firstIndex(where: { $0 === made }) else { return }
                self.pending.remove(at: i)
                self.changed()
            }
            // Already looking at that terminal: let the agent ask there instead.
            Focus.isFocused(s) { [weak self, weak made] focused in
                if focused, let made { self?.release(made) }
            }
        } else {
            conn.respond("")
        }
        changed()
    }

    func answer(_ p: Pending, output: String) {
        guard let i = pending.firstIndex(where: { $0 === p }) else { return }
        pending.remove(at: i)
        p.conn.respond(output)
        p.session.state = .working
        changed()
    }

    /// Hand the question back to the agent's own UI.
    func release(_ p: Pending) {
        guard let i = pending.firstIndex(where: { $0 === p }) else { return }
        pending.remove(at: i)
        p.conn.respond("")
        changed()
    }

    func markSeen(_ agent: String) {
        for s in sessions.values where s.agent == agent && s.state == .done { s.seen = true }
        changed()
    }

    // MARK: queries

    func sessions(of agent: String) -> [Session] {
        sessions.values.filter { $0.agent == agent }.sorted { a, b in
            let pa = pending.contains { $0.session === a }, pb = pending.contains { $0.session === b }
            if pa != pb { return pa }
            if displayRank(a) != displayRank(b) { return displayRank(a) > displayRank(b) }
            return a.updated > b.updated
        }
    }

    func summary(_ agent: String) -> AgentSummary? {
        let mine = sessions.values.filter { $0.agent == agent }
        guard !mine.isEmpty else { return nil }
        let top = mine.map(displayState).max() ?? .idle
        return AgentSummary(state: top, count: mine.count)
    }

    func displayState(_ s: Session) -> AgentState {
        if pending.contains(where: { $0.session === s }) { return .question }
        if s.state == .done && s.seen { return .idle }
        return s.state
    }

    private func displayRank(_ s: Session) -> Int { displayState(s).rawValue }

    // MARK: lifetime

    private func remove(_ key: String) {
        guard let s = sessions.removeValue(forKey: key) else { return }
        for p in pending where p.session === s { p.conn.respond("") }
        pending.removeAll { $0.session === s }
    }

    private func watchExit(_ pid: Int32) {
        guard exits[pid] == nil else { return }
        guard kill(pid, 0) == 0 || errno == EPERM else { return processExited(pid) }
        let src = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        src.setEventHandler { [weak self] in self?.processExited(pid) }
        exits[pid] = src
        src.resume()
    }

    private func processExited(_ pid: Int32) {
        exits.removeValue(forKey: pid)?.cancel()
        for (k, s) in sessions where s.pid == pid { remove(k) }
        changed()
    }

    private func changed() {
        scheduleLinger()
        onChange?()
        guard !saveQueued else { return }
        saveQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.saveQueued = false
            let all = Array(self.sessions.values)
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(all) { try? data.write(to: Self.url, options: .atomic) }
            }
        }
    }

    /// One wakeup at the next "done" expiry, none while nothing is pending.
    private func scheduleLinger() {
        let linger = config.config.doneLinger ?? 1200
        let next = sessions.values.filter { $0.state == .done && !$0.seen }.map { $0.updated.addingTimeInterval(linger) }.min()
        lingerToken += 1
        guard let next else { return }
        let token = lingerToken
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, next.timeIntervalSinceNow)) { [weak self] in
            guard let self, token == self.lingerToken else { return }
            let now = Date()
            for s in self.sessions.values where s.state == .done && !s.seen && s.updated.addingTimeInterval(linger) <= now { s.seen = true }
            self.changed()
        }
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.url), let all = try? JSONDecoder().decode([Session].self, from: data) else { return }
        for s in all where s.pid > 1 && (kill(s.pid, 0) == 0 || errno == EPERM) {
            // Whatever it was doing, we missed it; the next event corrects this.
            if s.state != .done { s.state = .idle }
            sessions[s.key] = s
            watchExit(s.pid)
        }
    }

    // MARK: debugging

    /// Event log, only written while ~/.agent-island/events.log exists.
    private static let logURL = islandHome.appendingPathComponent("events.log")
    private static let logHandle: FileHandle? = {
        guard let h = try? FileHandle(forWritingTo: logURL) else { return nil }
        h.seekToEndOfFile()
        return h
    }()

    static func debug(_ line: String) {
        logHandle?.write(Data("\(Date()) \(line)\n".utf8))
    }

    // MARK: payload parsing

    static func questions(_ input: [String: Any]) -> [Question]? {
        guard let raw = input["questions"] as? [[String: Any]], !raw.isEmpty else { return nil }
        return raw.map { q in
            let opts = (q["options"] as? [[String: Any]] ?? []).map { ($0["label"] as? String ?? "", $0["description"] as? String ?? "") }
            return Question(header: q["header"] as? String ?? "", text: q["question"] as? String ?? "",
                            options: opts.map { (label: $0.0, detail: $0.1) }, multi: q["multiSelect"] as? Bool ?? false)
        }
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.trimmingCharacters(in: .whitespaces).prefix(120))
    }

    static func describe(_ tool: String, _ input: Any?) -> String {
        let d = input as? [String: Any] ?? [:]
        let file = (d["file_path"] as? String ?? d["path"] as? String).map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Bash", "shell", "exec_command", "local_shell":
            if let desc = d["description"] as? String, !desc.isEmpty { return desc }
            return "Running " + firstLine(summarize(input))
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch": return "Editing " + (file ?? "files")
        case "Read": return "Reading " + (file ?? "files")
        case "Grep", "Glob": return "Searching the code"
        case "WebFetch", "WebSearch", "web_search": return "Browsing the web"
        case "Task", "Agent": return "Delegating to a subagent"
        case "TodoWrite", "update_plan": return "Planning"
        default: return tool.hasPrefix("mcp__") ? "Using " + (tool.split(separator: "_").dropFirst(2).first.map(String.init) ?? "a tool") : tool
        }
    }

    static func summarize(_ input: Any?) -> String {
        guard let d = input as? [String: Any] else { return "" }
        for k in ["command", "cmd", "file_path", "path", "url", "pattern"] {
            if let v = d[k] as? String { return v }
            if let v = d[k] as? [String] { return v.joined(separator: " ") }
        }
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).prefix(400))
    }
}
