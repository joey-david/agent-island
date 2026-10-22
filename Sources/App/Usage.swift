import Foundation

/// Rate-limit usage per agent, read only while a tray is open or when a limit is hit.
/// Claude: ~/.topnotchers/usage/claude.json, written by the status line.
/// Codex: the most recently written rollout log. Others: ~/.topnotchers/usage/<id>.json.
struct Usage {
    struct Window {
        let label: String     // "5h", "wk"
        let used: Double      // percent; 0 once its reset time has passed
        let resets: Date?

        init(_ label: String, used: Double, resets: Double?) {
            self.label = label
            self.resets = resets.map { Date(timeIntervalSince1970: $0) }
            self.used = self.resets.map { $0 < Date() } == true ? 0 : used
        }
    }
    /// Never empty.
    let windows: [Window]

    /// The window closest to its limit: the one that will stop you first.
    var binding: Window { windows.max { $0.used < $1.used }! }

    /// The tray re-renders on every hook event while open; re-read at most this often.
    private static var cache: [String: (at: Date, usage: Usage?)] = [:]

    static func read(_ agent: String, fresh: Bool = false) -> Usage? {
        if !fresh, let c = cache[agent], -c.at.timeIntervalSinceNow < 20 { return c.usage }
        let u = load(agent)
        cache[agent] = (Date(), u)
        return u
    }

    private static func load(_ agent: String) -> Usage? {
        if agent == "codex", let u = codex() { return u }
        let url = islandHome.appendingPathComponent("usage/\(agent).json")
        guard let data = try? Data(contentsOf: url),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let ws = [("five_hour", "5h"), ("seven_day", "wk")].compactMap { key, label -> Window? in
            guard let w = j[key] as? [String: Any], let pct = (w["used_percentage"] ?? w["used_percent"]) as? Double else { return nil }
            return Window(label, used: pct, resets: w["resets_at"] as? Double)
        }
        return ws.isEmpty ? nil : Usage(windows: ws)
    }

    private static func codex() -> Usage? {
        // sessions/YYYY/MM/DD: a thread logs under the day it started, so a long-running one
        // isn't in the newest folder. Check every log's mtime; they are a few hundred at most.
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        let logs = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                   options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "jsonl" }
        guard let newest = logs.max(by: { mtime($0) < mtime($1) }), let h = try? FileHandle(forReadingFrom: newest) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        // The last token count that carries limits (some carry only nulls for another limit id).
        guard let data = try? h.readToEnd(), case let text = String(decoding: data, as: UTF8.self),
              let r = text.range(of: "\"primary\":{", options: .backwards) else { return nil }
        let start = text[..<r.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
        let end = text[r.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        guard let j = (try? JSONSerialization.jsonObject(with: Data(text[start..<end].utf8))) as? [String: Any],
              let limits = (j["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { return nil }
        let ws = ["primary", "secondary"].compactMap { key -> Window? in
            guard let w = limits[key] as? [String: Any], let pct = w["used_percent"] as? Double else { return nil }
            return Window(label(minutes: w["window_minutes"] as? Int ?? 300), used: pct, resets: w["resets_at"] as? Double)
        }
        return ws.isEmpty ? nil : Usage(windows: ws)
    }

    private static func label(minutes m: Int) -> String {
        m == 10080 ? "wk" : m < 1440 ? "\(m / 60)h" : "\(m / 1440)d"
    }

    private static func mtime(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
