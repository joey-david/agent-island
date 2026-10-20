import AppKit

let islandHome = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".agent-island")
let maxAgents = 10

enum Side: String, Codable, CaseIterable { case left, right, hidden }

struct AgentConfig: Codable, Equatable {
    var id: String
    var name: String?
    var side: Side?
    /// "clawd", a sprite name in ~/.agent-island/sprites, a ~/.codex/pets name, or a path.
    var sprite: String?
    var color: String?
    /// Deep link for sessions running in an app rather than a terminal: {session}, {cwd}.
    var url: String?
    /// Bundle id to activate for app sessions without a deep link.
    var app: String?

    var displayName: String { name ?? id.prefix(1).uppercased() + id.dropFirst() }
    var placement: Side { side ?? .left }
    var tint: NSColor { NSColor(hex: color) ?? NSColor(white: 0.85, alpha: 1) }
}

struct Config: Codable {
    var agents: [AgentConfig]
    /// Seconds a finished session keeps its "done" dot before going quiet.
    var doneLinger: Double?
    var menuBarIcon: Bool?
    var launchAtLogin: Bool?

    static let initial = Config(agents: [
        AgentConfig(id: "claude", name: "Claude", side: .left, sprite: "clawd", color: "#D77757"),
        AgentConfig(id: "codex", name: "Codex", side: .right, sprite: "codex", color: "#9DB8FF",
                    url: "codex://threads/{session}", app: "com.openai.codex"),
    ], doneLinger: 1200, menuBarIcon: true, launchAtLogin: true)
}

final class ConfigStore {
    static let url = islandHome.appendingPathComponent("config.json")
    private(set) var config: Config
    var onChange: (() -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastData = Data()
    /// Demo autoplay: a fixed config that never touches the file.
    private var ephemeral = false

    init(fixed: Config) {
        config = fixed
        ephemeral = true
    }

    init() {
        try? FileManager.default.createDirectory(at: islandHome, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.url), let c = try? JSONDecoder().decode(Config.self, from: data) {
            config = c
            lastData = data
        } else {
            config = .initial
            if !FileManager.default.fileExists(atPath: Self.url.path) { save() }
        }
        watch()
    }

    func agent(_ id: String) -> AgentConfig? { config.agents.first { $0.id == id } }

    /// Unknown agents register themselves on the emptier side, up to `maxAgents`.
    func ensure(_ id: String) -> AgentConfig? {
        if let a = agent(id) { return a }
        guard config.agents.count < maxAgents else { return nil }
        let a = AgentConfig(id: id, side: emptierSide)
        update { $0.agents.append(a) }
        return a
    }

    var emptierSide: Side {
        let left = config.agents.filter { $0.placement == .left }.count
        let right = config.agents.filter { $0.placement == .right }.count
        return left <= right ? .left : .right
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config)
        config.agents = Array(config.agents.prefix(maxAgents))
        save()
        onChange?()
    }

    private func save() {
        guard !ephemeral else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(config) else { return }
        lastData = data
        try? data.write(to: Self.url, options: .atomic)
    }

    private func watch() {
        watcher?.cancel()
        let fd = open(Self.url.path, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.watch() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, unowned src] in
            let replaced = !src.data.isDisjoint(with: [.delete, .rename])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.reload()
                if replaced { self?.watch() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func reload() {
        guard let data = try? Data(contentsOf: Self.url), data != lastData,
              let c = try? JSONDecoder().decode(Config.self, from: data) else { return }
        lastData = data
        config = c
        onChange?()
    }
}

extension NSColor {
    convenience init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Open at login through a per-user LaunchAgent that just `open`s the app bundle.
enum LoginItem {
    static let plist = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents/fyi.joeydavid.agent-island.plist")
    static var enabled: Bool { FileManager.default.fileExists(atPath: plist.path) }

    static func sync(_ on: Bool) {
        guard on else { try? FileManager.default.removeItem(at: plist); return }
        let job: [String: Any] = ["Label": "fyi.joeydavid.agent-island", "RunAtLoad": true,
                                  "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath]]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0),
              (try? Data(contentsOf: plist)) != data else { return }
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: plist, options: .atomic)
    }
}
