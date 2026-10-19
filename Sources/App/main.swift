import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: ConfigStore!
    private var store: SessionStore!
    private var island: IslandController!
    private var menu: MenuController!
    private let server = Server()

    func applicationDidFinishLaunching(_ n: Notification) {
        config = ConfigStore()
        store = SessionStore(config: config)
        let stage = CommandLine.arguments.contains("--stage")
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
        server.start(path: islandHome.appendingPathComponent("island.sock").path) { [unowned self] msg, conn in
            self.store.handle(msg, conn: conn)
        }
        island.render(animated: false)
    }
}

signal(SIGPIPE, SIG_IGN)
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
