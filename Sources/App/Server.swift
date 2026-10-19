import Foundation

/// One hook invocation. Fire-and-forget hooks close right after their line;
/// `wait` hooks stay connected until `respond` (or until the agent kills them).
final class Connection {
    private let fd: Int32
    private let queue: DispatchQueue
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var delivered = false
    private var finished = false
    private var wait = false
    /// Called on main when a waiting hook disappears before it got an answer.
    var onHangup: (() -> Void)?

    init(fd: Int32, queue: DispatchQueue, deliver: @escaping ([String: Any], Connection) -> Void) {
        self.fd = fd
        self.queue = queue
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { self.readable(deliver) }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    private func readable(_ deliver: @escaping ([String: Any], Connection) -> Void) {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            guard !delivered else { return }
            buffer.append(chunk, count: n)
            guard let nl = buffer.firstIndex(of: 10) else {
                if buffer.count > 8_000_000 { finish() }
                return
            }
            delivered = true
            guard let obj = (try? JSONSerialization.jsonObject(with: buffer[..<nl])) as? [String: Any] else { return finish() }
            wait = obj["wait"] as? Bool ?? false
            DispatchQueue.main.async { deliver(obj, self) }
        } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
            if wait && !finished { DispatchQueue.main.async { self.onHangup?() } }
            finish()
        }
    }

    func respond(_ text: String) {
        queue.async {
            guard !self.finished else { return }
            if self.wait && !text.isEmpty {
                let bytes = Array(text.utf8)
                var off = 0
                while off < bytes.count {
                    let n = bytes[off...].withUnsafeBufferPointer { write(self.fd, $0.baseAddress, $0.count) }
                    if n > 0 { off += n } else if errno != EAGAIN && errno != EINTR { break } else { usleep(1000) }
                }
            }
            self.finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        source?.cancel()
        source = nil
    }
}

final class Server {
    private let queue = DispatchQueue(label: "island.io")
    private var listener: DispatchSourceRead?

    func start(path: String, deliver: @escaping ([String: Any], Connection) -> Void) {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(path.utf8.prefix(buf.count - 1))
            buf.copyBytes(from: bytes)
            buf[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 64) == 0 else { close(fd); NSLog("island: cannot listen on \(path)"); return }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [queue] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { break }
                _ = fcntl(c, F_SETFL, O_NONBLOCK)
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                _ = Connection(fd: c, queue: queue, deliver: deliver)
            }
        }
        src.resume()
        listener = src
    }
}
