import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: ConfigStore!
    private var store: SessionStore!
    private var island: IslandController!
    private var menu: MenuController!
    private let server = Server()
    private var autopilot: Autopilot?

    func applicationDidFinishLaunching(_ n: Notification) {
        let autoplay = CommandLine.arguments.contains("--autoplay")
        config = autoplay ? ConfigStore(fixed: Autopilot.config) : ConfigStore()
        store = SessionStore(config: config, persist: !autoplay)
        let stage = autoplay || CommandLine.arguments.contains("--stage")
        island = IslandController(store: store, config: config, stage: stage)
        if !stage && Bundle.main.bundlePath.contains("/Applications/") { LoginItem.sync(config.config.launchAtLogin ?? true) }
        menu = MenuController(config: config, store: store)
        menu.open = { [unowned self] s in self.island.openChat(s) }
        island.menu = { [unowned self] in self.menu.makeMenu() }
        store.onChange = { [unowned self] in self.island.render() }
        config.onChange = { [unowned self] in
            SpriteLibrary.reset()
            self.island.reload()
            self.menu.refreshItem()
        }
        island.render(animated: false)
        if autoplay {
            autopilot = Autopilot(store: store, island: island)
            autopilot?.run()
            return
        }
        server.start(path: islandHome.appendingPathComponent("island.sock").path) { [unowned self] msg, conn in
            self.store.handle(msg, conn: conn)
        }
    }
}

signal(SIGPIPE, SIG_IGN)
let demo = CommandLine.arguments.contains("--stage") || CommandLine.arguments.contains("--autoplay")
if !demo, let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
