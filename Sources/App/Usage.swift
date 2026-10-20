import Foundation

/// Rate-limit usage per agent, read only when a tray opens.
/// Claude: ~/.topnotchers/usage/claude.json, written by the status line.
/// Codex: the newest rollout log. Others: ~/.topnotchers/usage/<id>.json.
struct Usage {
    let fiveHour: Double      // percent used
    let resets: Date?

    static func read(_ agent: String) -> Usage? {
        if agent == "codex", let u = codex() { return u }
        let url = islandHome.appendingPathComponent("usage/\(agent).json")
        guard let data = try? Data(contentsOf: url),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let five = j["five_hour"] as? [String: Any],
              let pct = (five["used_percentage"] ?? five["used_percent"]) as? Double else { return nil }
        return Usage(fiveHour: pct, resets: (five["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) })
    }

    private static func codex() -> Usage? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        // sessions/YYYY/MM/DD: descend into the newest entry at each level.
        for _ in 0..<3 {
            guard let next = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter({ !$0.hasPrefix(".") }).max() else { return nil }
            dir.appendPathComponent(next)
        }
        let logs = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "jsonl" }
        guard let newest = logs.max(by: { mtime($0) < mtime($1) }), let h = try? FileHandle(forReadingFrom: newest) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8),
              let r = text.range(of: "\"primary\":{", options: .backwards) else { return nil }
        let tail = text[r.upperBound...].prefix(200)
        func num(_ key: String) -> Double? {
            guard let k = tail.range(of: "\"\(key)\":") else { return nil }
            return Double(tail[k.upperBound...].prefix { "0123456789.".contains($0) })
        }
        guard let pct = num("used_percent") else { return nil }
        return Usage(fiveHour: pct, resets: num("resets_at").map { Date(timeIntervalSince1970: $0) })
    }

    private static func mtime(_ u: URL) -> Date {
        (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
