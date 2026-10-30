import Foundation
import Darwin

/// Opt-in hook channel: a local Unix socket (0600, inside a 0700 folder) that a user-installed
/// permission hook talks to. The hook blocks until the user decides in Hubbub, or falls through to the
/// CLI's own prompt (timeout, Hubbub closed, channel off, "Ask in terminal").
enum HookDecision: String, Equatable {
    case allow, deny, passthrough
}

struct HookInput: Equatable {
    var format: String          // "claude" | "copilot"
    var sessionID: String
    var toolName: String
    var detail: String
    var cwd: String
    var timeout: TimeInterval

    /// Matches `SessionInfo.id` (Claude ids are prefixed, Copilot ids are bare).
    var sessionKey: String { format == "claude" ? "claude:\(sessionID)" : sessionID }
}

final class DecisionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _decision: HookDecision?
    private var _gone = false
    private var _message: String?
    func resolve(_ d: HookDecision, message: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        if _decision == nil { _decision = d; _message = message }
    }
    func markGone() { lock.lock(); _gone = true; lock.unlock() }
    var decision: (HookDecision, String?)? { lock.lock(); defer { lock.unlock() }; return _decision.map { ($0, _message) } }
    var gone: Bool { lock.lock(); defer { lock.unlock() }; return _gone }
}

enum ReplyHookProtocol {
    static let maxRequestBytes = 256 * 1024
    static let defaultTimeout: TimeInterval = 60

    static func socketDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hubbub", isDirectory: true).appendingPathComponent("reply", isDirectory: true)
    }
    static func socketPath() -> String { socketDirectory().appendingPathComponent("reply.sock").path }

    /// Parses the line a hook sends: `{"v":1,"format":..,"timeout":..,"input":{..original hook JSON..}}`.
    static func parseRequest(_ data: Data) -> HookInput? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], o["v"] as? Int == 1,
              let format = o["format"] as? String, ["claude", "copilot"].contains(format),
              let input = o["input"] as? [String: Any] else { return nil }
        let sid = (input["session_id"] as? String) ?? (input["sessionId"] as? String) ?? ""
        let tool = (input["tool_name"] as? String) ?? (input["toolName"] as? String) ?? ""
        guard !sid.isEmpty, !tool.isEmpty, sid.count < 200, tool.count < 200 else { return nil }
        var ti = input["tool_input"] ?? input["toolInput"] ?? input["toolArgs"]
        if let s = ti as? String, let d = try? JSONSerialization.jsonObject(with: Data(s.utf8)) { ti = d }
        let t = min(300, max(5, (o["timeout"] as? Double) ?? defaultTimeout))
        return HookInput(format: format, sessionID: sid, toolName: QuestionText.clean(tool, limit: 80),
                         detail: summarize(ti), cwd: (input["cwd"] as? String) ?? "", timeout: t)
    }

    static func summarize(_ toolInput: Any?) -> String {
        guard let d = toolInput as? [String: Any] else {
            return toolInput.map { QuestionText.clean("\($0)", limit: QuestionText.maxDetail) } ?? ""
        }
        for k in ["command", "file_path", "path", "url", "pattern", "query"] {
            if let s = d[k] as? String, !s.isEmpty {
                let desc = (d["description"] as? String).map { QuestionText.clean($0, limit: 160) }
                return QuestionText.clean(desc.map { "\($0)\n\(s)" } ?? s, limit: QuestionText.maxDetail, keepNewlines: true)
            }
        }
        let json = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return QuestionText.clean(json, limit: QuestionText.maxDetail)
    }

    /// What the hook prints to stdout; nil/empty means "no decision, use the normal prompt".
    static func render(format: String, decision: HookDecision, message: String?) -> String {
        let reason = message ?? "Denied by the user in Hubbub"
        func json(_ o: [String: Any]) -> String {
            (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
        switch (format, decision) {
        case (_, .passthrough): return ""
        case ("claude", .allow):
            return json(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "allow"]]])
        case ("claude", .deny):
            return json(["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "deny", "message": reason]]])
        case (_, .allow): return json(["behavior": "allow"])
        case (_, .deny): return json(["behavior": "deny", "message": reason])
        }
    }

    static func response(_ d: HookDecision, message: String? = nil) -> Data {
        var o: [String: Any] = ["v": 1, "decision": d.rawValue]
        if let message { o["message"] = message }
        return ((try? JSONSerialization.data(withJSONObject: o)) ?? Data()) + Data("\n".utf8)
    }
}

// MARK: Server

final class ReplyServer: @unchecked Sendable {
    typealias Handler = (HookInput, DecisionBox) -> Void
    typealias Finished = (DecisionBox) -> Void

    private let path: String
    private let handler: Handler
    private let finished: Finished
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private let lock = NSLock()
    private var active = 0
    static let maxActive = 8

    init(path: String, handler: @escaping Handler, finished: @escaping Finished) {
        self.path = path; self.handler = handler; self.finished = finished
    }

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return listenFD >= 0 }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(dir, 0o700)
        var st = stat()
        if lstat(path, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == geteuid() else { throw ReplyError("Refusing to replace a non-socket at the reply path") }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ReplyError("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); throw ReplyError("Socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let old = umask(0o177)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard rc == 0 else { close(fd); throw ReplyError("bind() failed") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); unlink(path); throw ReplyError("listen() failed") }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "hubbub.reply.accept"))
        src.setEventHandler { [weak self] in self?.acceptAll(fd) }
        src.resume()
        lock.lock(); listenFD = fd; listenSource = src; lock.unlock()
    }

    func stop() {
        lock.lock()
        let fd = listenFD
        listenFD = -1
        lock.unlock()
        listenSource?.cancel()
        listenSource = nil
        if fd >= 0 { close(fd); unlink(path) }
    }

    private func acceptAll(_ lfd: Int32) {
        while true {
            let c = accept(lfd, nil, nil)
            if c < 0 { return }
            lock.lock(); let ok = active < Self.maxActive; if ok { active += 1 }; lock.unlock()
            guard ok else { _ = Self.write(c, ReplyHookProtocol.response(.passthrough)); close(c); continue }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                serve(c)
                lock.lock(); active -= 1; lock.unlock()
            }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { return }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !data.contains(10) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return }
            data.append(buf, count: n)
            if data.count > ReplyHookProtocol.maxRequestBytes { return }
        }
        guard let line = data.split(separator: 10, maxSplits: 1, omittingEmptySubsequences: false).first,
              let input = ReplyHookProtocol.parseRequest(Data(line)) else {
            _ = Self.write(fd, ReplyHookProtocol.response(.passthrough)); return
        }
        let box = DecisionBox()
        handler(input, box)
        defer { finished(box) }
        let deadline = Date().addingTimeInterval(input.timeout)
        while Date() < deadline {
            if let (d, m) = box.decision { _ = Self.write(fd, ReplyHookProtocol.response(d, message: m)); return }
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&p, 1, 100) > 0, p.revents != 0 {
                var b: UInt8 = 0
                let n = recv(fd, &b, 1, MSG_PEEK | MSG_DONTWAIT)
                if n == 0 || (n < 0 && errno != EAGAIN) { box.markGone(); return }
            }
        }
        _ = Self.write(fd, ReplyHookProtocol.response(.passthrough))
    }

    private static func write(_ fd: Int32, _ d: Data) -> Bool {
        d.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, d.count) == d.count }
    }
}

// MARK: Client (`Hubbub --reply-hook <claude|copilot>`)

enum ReplyHookClient {
    /// Returns the text the hook should print. Every failure path returns "" so the CLI shows its own prompt.
    static func run(format: String, stdin: Data, timeout: TimeInterval, socketPath: String = ReplyHookProtocol.socketPath()) -> String {
        guard let input = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any] else { return "" }
        let req: [String: Any] = ["v": 1, "format": format, "timeout": timeout, "input": input]
        guard var payload = try? JSONSerialization.data(withJSONObject: req) else { return "" }
        payload.append(10)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return "" }
        defer { close(fd) }
        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return "" }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { return "" }
        let sent = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
        guard sent == payload.count else { return "" }
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout + 10)
        while !out.contains(10), Date() < deadline {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 500) > 0 else { continue }
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
            if out.count > 64 * 1024 { return "" }
        }
        guard let line = out.split(separator: 10).first,
              let o = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              o["v"] as? Int == 1, let d = (o["decision"] as? String).flatMap(HookDecision.init(rawValue:)) else { return "" }
        return ReplyHookProtocol.render(format: format, decision: d, message: o["message"] as? String)
    }

    /// Entry point for `--reply-hook`; always exits 0 so the CLI falls back to its normal prompt on any problem.
    static func main(arguments: [String]) -> Never {
        let format = arguments.firstIndex(of: "--reply-hook").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "claude"
        var timeout = ReplyHookProtocol.defaultTimeout
        if let i = arguments.firstIndex(of: "--timeout"), arguments.indices.contains(i + 1), let t = Double(arguments[i + 1]) { timeout = min(300, max(5, t)) }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let text = ["claude", "copilot"].contains(format) ? run(format: format, stdin: input, timeout: timeout) : ""
        if !text.isEmpty { print(text) }
        exit(0)
    }
}
