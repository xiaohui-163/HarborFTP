import Foundation
import Darwin

struct FTPConfig {
    var root: URL
    var port: UInt16
    var username: String
    var password: String
    var anonymous: Bool
    var writable: Bool
}
struct FTPConnection: Identifiable, Codable {
    let id: UUID
    let ip: String
    let connectedAt: Date
    var username: String?
    var activity: String
}
enum FTPError: Error { case failed(String); case response(Int, String) }
final class FTPServer {
    private let lock = NSLock()
    private let workers = DispatchGroup()
    private var listener: Int32 = -1
    private var generation = UUID()
    private var clients: [UUID: FTPSession] = [:]
    var log: (String) -> Void = { _ in }
    private var details: [UUID: FTPConnection] = [:]
    var connectionChanged: ([FTPConnection]) -> Void = { _ in }
    var connectionSnapshot: [FTPConnection] {
        lock.lock(); defer { lock.unlock() }
        return details.values.sorted { $0.connectedAt < $1.connectedAt }
    }
    private func publishConnections() {
        connectionChanged(details.values.sorted { $0.connectedAt < $1.connectedAt })
    }
    func start(_ config: FTPConfig) throws {
        lock.lock(); defer { lock.unlock() }
        guard listener < 0 else { throw FTPError.failed("服务已经启动") }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FTPError.failed("无法创建监听") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, 4)
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET); addr.sin_port = config.port.bigEndian
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); throw FTPError.failed("端口无法监听，可能已被占用") }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        listener = fd; generation = UUID(); let run = generation
        workers.enter()
        DispatchQueue.global().async { [self] in
            defer { workers.leave() }
            while true {
                lock.lock()
                guard generation == run, listener == fd else { lock.unlock(); return }
                let client = accept(fd, nil, nil)
                if client < 0 { lock.unlock(); usleep(20000); continue }
                guard clients.count < 32 else { close(client); lock.unlock(); continue }
                _ = fcntl(client, F_SETFL, 0)
                let session = FTPSession(fd: client, config: config, log: log)
                let id = session.id
                clients[id] = session
                details[id] = FTPConnection(id: id, ip: session.peerName, connectedAt: Date(), username: nil, activity: "等待登录")
                session.statusChanged = { [weak self] username, activity in
                    guard let self else { return }
                    self.lock.lock(); defer { self.lock.unlock() }
                    guard self.details[id] != nil else { return }
                    self.details[id]?.username = username
                    self.details[id]?.activity = activity
                    self.publishConnections()
                }
                publishConnections()
                workers.enter(); lock.unlock()
                DispatchQueue.global().async { [self] in
                    defer { workers.leave() }
                    session.run()
                    session.finish()
                    lock.lock(); clients.removeValue(forKey: id); details.removeValue(forKey: id)
                    publishConnections(); lock.unlock()
                }
            }
        }
    }
    func stop() {
        lock.lock()
        generation = UUID()
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
        for session in clients.values { session.cancel() }
        lock.unlock()
        // A stopped result means all sessions and their data listeners have exited.
        workers.wait()
    }
    deinit { stop() }
}
private final class FTPSession {
    let fd: Int32
    let config: FTPConfig
    let log: (String) -> Void
    private let socketLock = NSLock()
    private var cancelled = false
    private var sockets: Set<Int32> = []
    var isCancelled: Bool { socketLock.lock(); defer { socketLock.unlock() }; return cancelled }
    func track(_ socket: Int32) -> Bool {
        socketLock.lock(); defer { socketLock.unlock() }
        guard !cancelled else { close(socket); return false }
        sockets.insert(socket); return true
    }
    func release(_ socket: Int32) {
        socketLock.lock(); defer { socketLock.unlock() }
        if sockets.remove(socket) != nil { close(socket) }
    }
    func cancel() {
        socketLock.lock(); defer { socketLock.unlock() }
        cancelled = true
        for socket in sockets { shutdown(socket, SHUT_RDWR) }
    }
    func finish() {
        socketLock.lock(); defer { socketLock.unlock() }
        for socket in sockets { close(socket) }; sockets.removeAll()
    }
    let id = UUID()
    private var sessionID: String { String(id.uuidString.prefix(8)) }
    private var transferBytes: Int64 = 0
    var statusChanged: (String?, String) -> Void = { _, _ in }
    var peerName: String {
        var address = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &length) } }
        return result == 0 ? String(cString: inet_ntoa(address.sin_addr)) : "unknown"
    }
    private func event(_ message: String) {
        let clean = message.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        log("[\(sessionID)] \(clean)")
    }
    var cwd = "/", user = "", authenticated = false
    var passive: Int32 = -1
    var renameFrom: URL?
    var root: URL { config.root.resolvingSymlinksInPath().standardizedFileURL }
    init(fd: Int32, config: FTPConfig, log: @escaping (String) -> Void) { self.fd = fd; self.config = config; self.log = log; sockets.insert(fd) }
    func send(_ socket: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                if isCancelled { return false }
                let n = Darwin.send(socket, bytes.baseAddress!.advanced(by: offset), data.count - offset, 0)
                if n <= 0 { return false }; offset += n
            }; return true
        }
    }
    func reply(_ text: String) { _ = send(fd, Data((text + "\r\n").utf8)) }
    func path(_ input: String) throws -> URL {
        let relative = input.hasPrefix("/") ? input : cwd + "/" + input
        let result = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard result.path == root.path || result.path.hasPrefix(root.path + "/") else { throw FTPError.failed("路径超出共享目录") }
        return result
    }
    func preparePassive(extended: Bool) {
        if passive >= 0 { release(passive); passive = -1 }
        let s = socket(AF_INET, SOCK_STREAM, 0)
        guard s >= 0 else { reply("425 Cannot create data socket"); return }
        guard track(s) else { return }
        var addr = sockaddr_in(); addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); addr.sin_family = sa_family_t(AF_INET)
        let ok = withUnsafeMutablePointer(to: &addr) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0, listen(s, 1) == 0 else { release(s); reply("425 Cannot listen"); return }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(s, $0, &len) } }
        let port = UInt16(bigEndian: addr.sin_port)
        _ = fcntl(s, F_SETFL, O_NONBLOCK)
        passive = s
        if extended { reply("229 Entering Extended Passive Mode (|||\(port)|)") }
        else {
            var local = sockaddr_in()
            withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) } }
            let ip = String(cString: inet_ntoa(local.sin_addr)).replacingOccurrences(of: ".", with: ",")
            reply("227 Entering Passive Mode (\(ip),\(port / 256),\(port % 256))")
        }
    }
    func transfer(_ operation: (Int32) throws -> Void) throws {
        guard !isCancelled else { throw FTPError.failed("服务已停止") }
        guard passive >= 0 else { throw FTPError.response(425, "Use PASV or EPSV first") }
        let p = passive; passive = -1
        defer { release(p) }
        reply("150 Opening data connection")
        var poller = pollfd(fd: p, events: Int16(POLLIN), revents: 0)
        var ready = false
        for _ in 0..<100 {
            if isCancelled { throw FTPError.failed("服务已停止") }
            if poll(&poller, 1, 100) > 0 { ready = true; break }
        }
        guard !isCancelled else { throw FTPError.failed("服务已停止") }
        guard ready else { throw FTPError.response(425, "Data connection timed out") }
        var peer = sockaddr_in(), controlPeer = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let data = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(p, $0, &len) } }
        guard data >= 0 else { throw FTPError.response(425, "Data connection failed") }
        guard track(data) else { throw FTPError.failed("服务已停止") }
        defer { release(data) }
        _ = fcntl(data, F_SETFL, 0)
        configure(data)
        withUnsafeMutablePointer(to: &controlPeer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getpeername(fd, $0, &len) } }
        guard peer.sin_addr.s_addr == controlPeer.sin_addr.s_addr else { throw FTPError.response(425, "Peer mismatch") }
        try operation(data)
        guard !isCancelled else { throw FTPError.failed("服务已停止") }
        reply("226 Transfer complete")
    }
    func configure(_ s: Int32) {
        var yes: Int32 = 1; setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &yes, 4)
        var timeout = timeval(tv_sec: 60, tv_usec: 0)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    func run() {
        configure(fd); reply("220 Harbor FTP ready"); event("客户端已连接 · \(peerName)")
        defer { if passive >= 0 { release(passive) }; event("客户端已断开") }
        var pending = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = recv(fd, &buffer, buffer.count, 0); if n <= 0 { return }
            pending.append(contentsOf: buffer.prefix(n))
            if pending.count > 65536 { reply("500 Command too long"); return }
            while let range = pending.range(of: Data([13,10])) {
                if isCancelled { return }
                let line = String(decoding: pending[..<range.lowerBound], as: UTF8.self)
                pending.removeSubrange(..<range.upperBound)
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                let command = String(parts.first ?? "").uppercased(), arg = parts.count > 1 ? String(parts[1]) : ""
                if command == "QUIT" { reply("221 Goodbye"); return }
                let direction = command == "STOR" ? "上传" : command == "RETR" ? "下载" : nil
                let started = Date()
                transferBytes = 0
                if let direction { event("\(direction)开始 · \(arg) · 用户 \(user)") }
                statusChanged(authenticated ? user : nil, direction.map { "\($0) · \(arg)" } ?? "处理 \(command)")
                defer { statusChanged(authenticated ? user : nil, authenticated ? "空闲" : "等待登录") }
                do {
                    try handle(command, arg)
                    if let direction {
                        event("\(direction)完成 · \(arg) · \(transferBytes) 字节 · \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒")
                    }
                } catch {
                    let reason: String
                    if case FTPError.response(let code, let message) = error {
                        reply("\(code) \(message)"); reason = message
                    } else {
                        reply("550 Operation failed"); reason = String(describing: error)
                    }
                    if let direction {
                        event("\(direction)\(isCancelled ? "中断" : "失败") · \(arg) · \(transferBytes) 字节 · \(isCancelled ? "服务已停止" : reason)")
                    } else if !isCancelled {
                        event("操作失败 · \(command) · \(reason)")
                    }
                }
            }
        }
    }
    func handle(_ cmd: String, _ arg: String) throws {
        switch cmd {
        case "USER": user = arg; authenticated = false; reply("331 Password required"); return
        case "PASS": authenticated = (config.anonymous && user == "anonymous") || (user == config.username && arg == config.password); reply(authenticated ? "230 Logged in" : "530 Login incorrect"); if authenticated { event("用户 \(user) 已登录") }; return
        case "SYST": reply("215 UNIX Type: L8"); return
        case "FEAT": reply("211-Features\r\n UTF8\r\n EPSV\r\n SIZE\r\n MDTM\r\n211 End"); return
        case "NOOP": reply("200 OK"); return
        default: break
        }
        guard authenticated else { throw FTPError.response(530, "Login first") }
        switch cmd {
        case "OPTS": reply(arg.uppercased() == "UTF8 ON" ? "200 UTF8 enabled" : "501 Unsupported option")
        case "TYPE": reply(["I", "A"].contains(arg.uppercased()) ? "200 Type set" : "504 Unsupported type")
        case "PWD", "XPWD": reply("257 \"\(cwd.replacingOccurrences(of: "\"", with: "\"\""))\"")
        case "CWD", "CDUP":
            let url = try path(cmd == "CDUP" ? ".." : arg); var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { reply("550 Not a directory"); return }
            cwd = String(url.path.dropFirst(root.path.count)); if cwd.isEmpty { cwd = "/" }; reply("250 Directory changed")
        case "PASV": preparePassive(extended: false)
        case "EPSV": preparePassive(extended: true)
        case "LIST", "NLST":
            let url = try path(arg.isEmpty || arg.hasPrefix("-") ? "." : arg)
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
            let listing = try files.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { file -> String in
                let name = file.lastPathComponent.replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
                if cmd == "NLST" { return name }
                let v = try file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                return "\(v.isDirectory == true ? "d" : "-")rwxr-xr-x 1 owner group \(v.fileSize ?? 0) Jan 01 2026 \(name)"
            }.joined(separator: "\r\n") + "\r\n"
            try transfer { s in if !send(s, Data(listing.utf8)) { throw FTPError.failed("send") } }
        case "SIZE": let attrs = try FileManager.default.attributesOfItem(atPath: path(arg).path); reply("213 \(attrs[.size] ?? 0)")
        case "MDTM":
            let attrs = try FileManager.default.attributesOfItem(atPath: path(arg).path)
            let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMddHHmmss"
            reply("213 \(formatter.string(from: attrs[.modificationDate] as? Date ?? Date()))")
        case "RETR":
            let url = try path(arg); let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            try transfer { s in while let chunk = try file.read(upToCount: 65536), !chunk.isEmpty { if !send(s, chunk) { throw FTPError.failed("send") }; transferBytes += Int64(chunk.count) } }
        case "STOR", "DELE", "MKD", "RMD", "RNFR", "RNTO":
            guard config.writable, user != "anonymous" else { throw FTPError.response(550, "Read only") }
            let url = try path(arg)
            guard url != root else { throw FTPError.response(550, "Root protected") }
            switch cmd {
            case "STOR":
                let temp = url.deletingLastPathComponent().appendingPathComponent(".harbor-" + UUID().uuidString)
                guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw FTPError.failed("create") }
                defer { try? FileManager.default.removeItem(at: temp) }
                let file = try FileHandle(forWritingTo: temp); defer { try? file.close() }
                try transfer { s in
                    var buf = [UInt8](repeating: 0, count: 65536)
                    while true { let n = recv(s, &buf, buf.count, 0); if n == 0 { break }; if n < 0 { throw FTPError.failed("recv") }; try file.write(contentsOf: Data(buf.prefix(n))); transferBytes += Int64(n) }
                    try file.synchronize()
                    socketLock.lock(); defer { socketLock.unlock() }
                    guard !cancelled else { throw FTPError.failed("服务已停止") }
                    guard Darwin.rename(temp.path, url.path) == 0 else { throw FTPError.failed("rename") }
                }
            case "MKD": try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); reply("257 Directory created")
            case "DELE": guard unlink(url.path) == 0 else { throw FTPError.failed("delete") }; reply("250 Deleted")
            case "RMD": guard rmdir(url.path) == 0 else { throw FTPError.failed("rmdir") }; reply("250 Removed")
            case "RNFR": guard FileManager.default.fileExists(atPath: url.path) else { throw FTPError.failed("missing") }; renameFrom = url; reply("350 Send RNTO")
            default: guard let from = renameFrom else { reply("503 RNFR required"); return }; renameFrom = nil; try FileManager.default.moveItem(at: from, to: url); reply("250 Renamed")
            }
        default: event("不支持的命令 · \(cmd)"); reply("502 Command not implemented")
        }
    }
}
