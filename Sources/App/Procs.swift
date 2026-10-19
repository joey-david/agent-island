import Darwin

/// Just enough process inspection to see through Codex's shared app-server daemon:
/// its hooks all come from the daemon, so we find the terminal `codex` each session belongs to.
enum Procs {
    struct Info { let pid: pid_t; let comm: String; let tty: dev_t; let start: UInt64 }

    static func info(_ pid: pid_t) -> Info? {
        var bi = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bi, size) == size else { return nil }
        let comm = withUnsafeBytes(of: bi.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Info(pid: pid, comm: comm, tty: dev_t(bitPattern: bi.e_tdev), start: bi.pbi_start_tvsec)
    }

    static func path(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
    }

    static func cwd(_ pid: pid_t) -> String? {
        var vi = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vi, size) == size else { return nil }
        return withUnsafeBytes(of: vi.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static func all() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(0, got)))).filter { $0 > 0 }
    }

    static func isSharedDaemon(_ pid: pid_t) -> Bool { path(pid).contains("/app-server-daemon/") }

    /// Codex TUIs: a `codex` binary on a terminal, other than the daemon.
    static func codexClients() -> [Info] {
        all().compactMap(info).filter { $0.comm == "codex" && $0.tty != -1 && $0.tty != 0 && !isSharedDaemon($0.pid) }
    }
}
