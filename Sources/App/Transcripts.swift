import Foundation

/// Follows a busy session's transcript for what its hooks never report: a Ctrl+C or Esc, and a
/// turn that a usage limit or another error ended. Only bytes appended since the start are read.
final class TranscriptWatch {
    enum Stop { case interrupted(String?), limited }

    let path: String
    private let fd: Int32
    private let src: DispatchSourceFileSystemObject
    private var offset: off_t
    private var partial = Data()
    private var buf = [UInt8](repeating: 0, count: 65536)

    init?(path: String, onStop: @escaping (Stop) -> Void) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        self.path = path
        self.fd = fd
        offset = lseek(fd, 0, SEEK_END)
        src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.extend, .write], queue: .main)
        src.setEventHandler { [weak self] in self?.drain(onStop) }
        src.setCancelHandler { close(fd) }
        src.resume()
    }

    deinit { src.cancel() }

    private func drain(_ onStop: (Stop) -> Void) {
        while true {
            let n = pread(fd, &buf, buf.count, offset)
            if n <= 0 { break }
            offset += off_t(n)
            partial.append(contentsOf: buf[..<n])
        }
        guard let nl = partial.lastIndex(of: 10) else { return }
        let done = partial[..<nl]
        // Most appends hold no marker: a byte search, and only a hit is decoded.
        let hit = done.withUnsafeBytes { raw in
            Self.markerBytes.contains { m in m.withUnsafeBytes { memmem(raw.baseAddress, raw.count, $0.baseAddress, $0.count) != nil } }
        }
        if hit {
            for line in String(decoding: done, as: UTF8.self).split(separator: "\n") {
                if let stop = Self.stop(line) { onStop(stop) }
            }
        }
        partial.removeSubrange(..<(nl + 1))
    }

    // Unescaped quotes: tool output quoting these strings can't match.
    private static let markerBytes = markers.map { Data($0.utf8) }
    private static let markers = ["{\"type\":\"text\",\"text\":\"[Request interrupted by user", "\"isApiErrorMessage\":true",
                                  "{\"type\":\"turn_aborted\"", "\"codex_error_info\":"]

    static func stop(_ line: Substring) -> Stop? {
        // Claude Code
        if line.contains(markers[0]) { return .interrupted(nil) }
        if line.contains(markers[1]) {
            return line.contains("\"error\":\"rate_limit\"") || line.contains("\"error\":\"billing_error\"") ? .limited : nil
        }
        // Codex
        if line.contains(markers[2]) { return .interrupted(nil) }
        if line.contains("{\"type\":\"task_complete\""), let r = line.range(of: "\"codex_error_info\":\"([a-z_]+)\"", options: .regularExpression) {
            let code = line[r].split(separator: "\"").last.map(String.init) ?? ""
            return code == "usage_limit_exceeded" ? .limited : .interrupted(reason(code))
        }
        return nil
    }

    /// How the transcript's last turn ended, if it was stopped: for sessions restored after a relaunch.
    static func last(_ path: String) -> Stop? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 1 << 20 ? size - (1 << 20) : 0)
        guard let data = try? h.readToEnd() else { return nil }
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            // Codex marks turn boundaries; in Claude Code's, the last message says it.
            if line.contains("{\"type\":\"task_started\"") { return nil }
            if line.contains("{\"type\":\"task_complete\"") || line.contains(markers[2]) { return stop(line) }
            if line.contains(",\"type\":\"user\",") || line.contains(",\"type\":\"assistant\",") { return stop(line) }
        }
        return nil
    }

    /// Where an agent keeps a session's transcript, for sessions saved without its path.
    static func find(agent: String, id: String) -> String? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let fm = FileManager.default
        switch agent {
        case "codex":
            let root = home.appendingPathComponent(".codex/sessions")
            let all = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?.allObjects as? [URL] ?? []
            return all.first { $0.lastPathComponent.hasSuffix("-\(id).jsonl") }?.path
        case "claude":
            let root = home.appendingPathComponent(".claude/projects")
            return ((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
                .map { root.appendingPathComponent($0).appendingPathComponent(id + ".jsonl").path }
                .first(where: fm.fileExists)
        default:
            return nil
        }
    }

    /// "context_window_exceeded" → "Stopped: context window exceeded".
    static func reason(_ code: String) -> String {
        "Stopped: " + code.replacingOccurrences(of: "_", with: " ")
    }
}
