// topnotchers-hook: forwards an agent hook event to Topnotchers over a Unix socket.
//
//   topnotchers-hook --agent claude [--wait]           hook JSON on stdin
//   topnotchers-hook emit --agent aider --state working [--session S] [--cwd DIR]
//                    [--prompt TASK] [--action TEXT] [--pid PID]
//
// Exits 0 immediately when the app isn't running. With --wait it blocks for the
// app's reply (an answered question) and prints it for the agent to read.
import Darwin
import Foundation

var agent = "agent", wait = false, emit = false
var state: String?, event: String?, session: String?, cwd: String?, prompt: String?, action: String?
var pidArg: pid_t?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--agent": agent = args.next() ?? agent
    case "--wait": wait = true
    case "--event": event = args.next()
    case "--state": state = args.next()
    case "--session": session = args.next()
    case "--cwd": cwd = args.next()
    case "--prompt": prompt = args.next()
    case "--action": action = args.next()
    case "--pid": pidArg = args.next().flatMap { pid_t($0) }
    case "emit": emit = true
    default: break
    }
}

var payload: Any = [String: Any]()
if !emit && isatty(0) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if let obj = try? JSONSerialization.jsonObject(with: data) { payload = obj }
}

func procInfo(_ pid: pid_t) -> (ppid: pid_t, comm: String, tdev: dev_t)? {
    var kp = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
    let comm = withUnsafeBytes(of: kp.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    return (kp.kp_eproc.e_ppid, comm, kp.kp_eproc.e_tdev)
}

// The agent is the first ancestor that isn't a shell wrapping the hook command.
let shells: Set = ["sh", "bash", "zsh", "dash", "fish", "env"]
var pid = getppid()
var tty: String?
for _ in 0..<8 {
    guard let info = procInfo(pid) else { break }
    if !shells.contains(info.comm) {
        if info.tdev != -1, let name = devname(info.tdev, S_IFCHR) { tty = String(cString: name) }
        break
    }
    if info.ppid <= 1 { break }
    pid = info.ppid
}

if let pidArg { pid = pidArg }

let env = ProcessInfo.processInfo.environment
var msg: [String: Any] = ["v": 1, "agent": agent, "wait": wait, "pid": Int(pid), "payload": payload]
msg["event"] = event ?? (emit ? "emit" : nil)
msg["state"] = state
msg["session"] = session
msg["prompt"] = prompt
msg["action"] = action
msg["cwd"] = cwd ?? (emit ? FileManager.default.currentDirectoryPath : nil)
msg["tty"] = tty
msg["term"] = env["TERM_PROGRAM"]
msg["bundle"] = env["__CFBundleIdentifier"]

let path = NSHomeDirectory() + "/.topnotchers/topnotchers.sock"
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { buf in
    let bytes = Array(path.utf8.prefix(buf.count - 1))
    buf.copyBytes(from: bytes)
    buf[bytes.count] = 0
}
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard connected == 0 else { exit(0) }
var one: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

guard var data = try? JSONSerialization.data(withJSONObject: msg) else { exit(0) }
data.append(10)
data.withUnsafeBytes { raw in
    var off = 0
    while off < raw.count {
        let n = write(fd, raw.baseAddress! + off, raw.count - off)
        if n <= 0 { break }
        off += n
    }
}

if wait {
    var out = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        out.append(buf, count: n)
    }
    FileHandle.standardOutput.write(out)
}
close(fd)
exit(0)
