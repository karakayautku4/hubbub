import AppKit
import Foundation

/// What the user chose in Hubbub. Never created automatically.
enum ReplyAnswer: Equatable {
    case approve
    case deny
    case choice(Int)
    case text(String)
}

/// One keystroke aimed at a terminal.
enum KeyStroke: Equatable {
    case text(String), enter, down, up, escape, tab

    /// Raw bytes as a terminal would receive them (used for iTerm2 `write text`).
    var raw: String {
        switch self {
        case .text(let s): s
        case .enter: "\r"
        case .down: "\u{1B}[B"
        case .up: "\u{1B}[A"
        case .escape: "\u{1B}"
        case .tab: "\t"
        }
    }

    var tmuxName: String? {
        switch self { case .enter: "Enter"; case .down: "Down"; case .up: "Up"; case .escape: "Escape"; case .tab: "Tab"; case .text: nil }
    }
}

/// Maps an answer to the keystrokes the agent's terminal UI expects.
/// The key layout is an assumption about each CLI's prompt (first option highlighted, Esc cancels); it is
/// deliberately kept in this one table so it is easy to correct. See docs/REPLY.md ("Unverified").
enum ReplyFormatter {
    static let maxTextLength = 2000

    static func keys(for answer: ReplyAnswer, question q: PendingQuestion, provider: String) -> Result<[KeyStroke], ReplyError> {
        switch answer {
        case .approve, .deny:
            guard q.isPermission else { return .failure(.init("This isn't an approval question")) }
            return .success(answer == .approve ? [.enter] : [.escape])
        case .choice(let i):
            guard q.kind == .choice, q.canAnswerInApp, q.options.indices.contains(i) else {
                return .failure(.init("This question can only be answered in the terminal"))
            }
            return .success(Array(repeating: KeyStroke.down, count: i) + [.enter])
        case .text(let raw):
            guard q.kind == .freeText || q.allowsFreeText else { return .failure(.init("This question has no free-text answer")) }
            let t = QuestionText.clean(raw, limit: maxTextLength)
            guard !t.isEmpty else { return .failure(.init("Type a reply first")) }
            return .success([.text(t), .enter])
        }
    }
}

struct ReplyError: Error, Equatable {
    let message: String
    init(_ m: String) { message = m }
}

/// Outcome of handing an answer to a channel. `sent` means "dispatched", never "the agent received it".
enum DeliveryResult: Equatable {
    case sent(via: String)
    case failed(String)
}

enum ChannelOutcome: Equatable {
    case sent(String)
    case notApplicable(String)
    case failed(String)
}

// MARK: Process access (faked in tests)

struct CommandResult: Equatable {
    var status: Int32
    var out: String
    var err: String
}

protocol CommandRunner {
    func run(_ exe: String, _ args: [String]) -> CommandResult
}

struct SystemRunner: CommandRunner {
    var timeout: TimeInterval = 5
    func run(_ exe: String, _ args: [String]) -> CommandResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return CommandResult(status: 127, out: "", err: error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = o.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = e.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { p.terminate(); group.wait(); return CommandResult(status: 124, out: "", err: "timed out") }
        group.wait()
        return CommandResult(status: p.terminationStatus, out: String(decoding: outData, as: UTF8.self), err: String(decoding: errData, as: UTF8.self))
    }
}

struct ReplyEnvironment {
    var fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    var isAppRunning: (String) -> Bool = { id in !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }
}

// MARK: Finding the terminal of a session

struct ProcRow: Equatable {
    var pid: Int32
    var ppid: Int32
    var tty: String
    var command: String
}

enum TTYLocator {
    enum Result: Equatable {
        case found(tty: String, how: String)
        case ambiguous(Int)
        case notFound
    }

    static let processNames: [String: [String]] = [
        "copilot": ["copilot"], "claude": ["claude"], "codex": ["codex"],
        "gemini": ["gemini"], "cursor": ["cursor-agent", "agent"], "grok": ["grok"],
    ]

    /// Parses `ps -axo pid=,ppid=,tty=,command=`.
    static func parsePS(_ text: String) -> [ProcRow] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
            return ProcRow(pid: pid, ppid: ppid, tty: String(parts[2]), command: String(parts[3]))
        }
    }

    static func hasTTY(_ r: ProcRow) -> Bool { r.tty != "??" && r.tty != "?" && r.tty != "-" && !r.tty.isEmpty }

    static func looksLikeAgent(_ r: ProcRow, provider: String) -> Bool {
        let names = processNames[provider] ?? [provider]
        let tokens = r.command.split(separator: " ").prefix(2).map { ($0 as NSString).lastPathComponent }
        return tokens.contains { names.contains($0) }
    }

    /// Order of confidence: session id on the command line, a pid hint (lock file), then a unique working directory.
    static func locate(provider: String, rawID: String, cwd: String, hintPIDs: [Int32], rows: [ProcRow],
                       cwdOf: (Int32) -> String?) -> Result {
        func verdict(_ rs: [ProcRow], _ how: String) -> Result? {
            let ttys = Set(rs.filter(hasTTY).map(\.tty))
            if ttys.count == 1, let t = ttys.first { return .found(tty: t, how: how) }
            return ttys.count > 1 ? .ambiguous(ttys.count) : nil
        }
        if rawID.count >= 8, let r = verdict(rows.filter { $0.command.contains(rawID) && looksLikeAgent($0, provider: provider) }, "session id") { return r }
        if let r = verdict(rows.filter { hintPIDs.contains($0.pid) }, "process lock") { return r }
        guard !cwd.isEmpty else { return .notFound }
        let candidates = rows.filter { hasTTY($0) && looksLikeAgent($0, provider: provider) && cwdOf($0.pid) == cwd }
        return verdict(candidates, "working directory") ?? .notFound
    }
}

// MARK: Channels

struct ReplyContext {
    var provider: String
    var rawID: String
    var cwd: String
    var hintPIDs: [Int32] = []
}

enum TmuxPanes {
    /// Parses `list-panes -a -F "#{pane_id}\t#{pane_tty}"`.
    static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 1)
            if p.count == 2 { out[String(p[1])] = String(p[0]) }
        }
        return out
    }

    static func commands(for keys: [KeyStroke], pane: String) -> [[String]] {
        keys.map { k in
            if case .text(let s) = k { return ["send-keys", "-t", pane, "-l", "--", s] }
            return ["send-keys", "-t", pane, k.tmuxName ?? "Enter"]
        }
    }
}

struct TmuxChannel {
    let runner: CommandRunner
    let env: ReplyEnvironment
    static let paths = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    func deliver(_ keys: [KeyStroke], tty: String) -> ChannelOutcome {
        guard let exe = Self.paths.first(where: env.fileExists) else { return .notApplicable("tmux isn't installed") }
        let list = runner.run(exe, ["list-panes", "-a", "-F", "#{pane_id}\t#{pane_tty}"])
        guard list.status == 0 else { return .notApplicable("no tmux server is running") }
        guard let pane = TmuxPanes.parse(list.out)["/dev/" + tty] else { return .notApplicable("the session isn't in a tmux pane") }
        for cmd in TmuxPanes.commands(for: keys, pane: pane) {
            let r = runner.run(exe, cmd)
            if r.status != 0 { return .failed("tmux refused the keys: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
        }
        return .sent("tmux")
    }
}

/// Terminal.app and iTerm2 are driven with `osascript`; the tty and the payload travel as argv, never inside script source.
struct AppleScriptChannel {
    enum App { case terminal, iterm
        var bundleID: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }
        var name: String { self == .terminal ? "Terminal" : "iTerm2" }
    }
    let app: App
    let runner: CommandRunner
    let env: ReplyEnvironment

    static func script(for app: App) -> [String] {
        let find: [String]
        switch app {
        case .terminal:
            find = ["repeat with t in tabs of w", "if (tty of t) is theTTY then", "do script payload in t", "return \"ok\"", "end if", "end repeat"]
        case .iterm:
            find = ["repeat with t in tabs of w", "repeat with s in sessions of t", "if (tty of s) is theTTY then",
                    "tell s to write text payload newline NO", "return \"ok\"", "end if", "end repeat", "end repeat"]
        }
        return ["on run argv", "set theTTY to item 1 of argv", "set payload to item 2 of argv",
                "tell application id \"\(app.bundleID)\"", "repeat with w in windows"] + find
            + ["end repeat", "end tell", "return \"notfound\"", "end run"]
    }

    /// Terminal.app's `do script` always appends a return, so only "text + Enter" or a bare Enter can be expressed.
    static func payload(_ keys: [KeyStroke], for app: App) -> String? {
        switch app {
        case .iterm: return keys.map(\.raw).joined()
        case .terminal:
            if keys == [.enter] { return "" }
            if keys.count == 2, case .text(let s) = keys[0], keys[1] == .enter { return s }
            return nil
        }
    }

    func deliver(_ keys: [KeyStroke], tty: String) -> ChannelOutcome {
        guard env.isAppRunning(app.bundleID) else { return .notApplicable("\(app.name) isn't running") }
        guard let payload = Self.payload(keys, for: app) else {
            return .notApplicable("\(app.name) can't receive these keys (needs tmux or iTerm2)")
        }
        let args = Self.script(for: app).flatMap { ["-e", $0] } + ["--", "/dev/" + tty, payload]
        let r = runner.run("/usr/bin/osascript", args)
        if r.status != 0 {
            if r.err.contains("-1743") {
                return .failed("macOS blocked Hubbub from controlling \(app.name). Allow it in System Settings → Privacy & Security → Automation.")
            }
            return .failed("\(app.name) didn't accept the keys")
        }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
            ? .sent(app.name) : .notApplicable("the session isn't in a \(app.name) tab")
    }
}

/// Brings the terminal tab a session runs in to the front (Terminal.app and iTerm2); tmux panes can't be focused from outside.
struct TerminalFocus {
    var runner: CommandRunner = SystemRunner()
    var env = ReplyEnvironment()

    static func script(for app: AppleScriptChannel.App) -> [String] {
        let find: [String]
        switch app {
        case .terminal:
            find = ["repeat with t in tabs of w", "if (tty of t) is theTTY then", "set selected of t to true", "set index of w to 1",
                    "activate", "return \"ok\"", "end if", "end repeat"]
        case .iterm:
            find = ["repeat with t in tabs of w", "repeat with s in sessions of t", "if (tty of s) is theTTY then",
                    "tell w to select", "tell t to select", "tell s to select", "activate", "return \"ok\"", "end if", "end repeat", "end repeat"]
        }
        return ["on run argv", "set theTTY to item 1 of argv", "tell application id \"\(app.bundleID)\"", "repeat with w in windows"] + find
            + ["end repeat", "end tell", "return \"notfound\"", "end run"]
    }

    /// Returns the terminal app that now shows the session, or nil with a reason.
    func focus(_ ctx: ReplyContext) -> (app: String?, reason: String?) {
        let ps = runner.run("/bin/ps", ["-axo", "pid=,ppid=,tty=,command="])
        guard ps.status == 0 else { return (nil, "Couldn't list processes") }
        let located = TTYLocator.locate(provider: ctx.provider, rawID: ctx.rawID, cwd: ctx.cwd, hintPIDs: ctx.hintPIDs,
                                        rows: TTYLocator.parsePS(ps.out)) { pid in
            let r = runner.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])
            return r.out.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        }
        guard case .found(let tty, _) = located else { return (nil, "Couldn't find the terminal this session runs in") }
        var blocked = false
        for app in [AppleScriptChannel.App.iterm, .terminal] where env.isAppRunning(app.bundleID) {
            let args = Self.script(for: app).flatMap { ["-e", $0] } + ["--", "/dev/" + tty]
            let r = runner.run("/usr/bin/osascript", args)
            if r.status != 0 { if r.err.contains("-1743") { blocked = true }; continue }
            if r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" { return (app.name, nil) }
        }
        return (nil, blocked ? "macOS blocked Hubbub from controlling the terminal (System Settings → Privacy & Security → Automation)" : "The session isn't in a Terminal or iTerm2 tab")
    }
}

/// Finds the session's terminal and tries tmux, iTerm2 and Terminal.app in turn.
struct TTYDelivery {
    var runner: CommandRunner = SystemRunner()
    var env = ReplyEnvironment()

    func deliver(_ keys: [KeyStroke], ctx: ReplyContext) -> DeliveryResult {
        let ps = runner.run("/bin/ps", ["-axo", "pid=,ppid=,tty=,command="])
        guard ps.status == 0 else { return .failed("Couldn't list processes") }
        let located = TTYLocator.locate(provider: ctx.provider, rawID: ctx.rawID, cwd: ctx.cwd, hintPIDs: ctx.hintPIDs,
                                        rows: TTYLocator.parsePS(ps.out)) { pid in
            let r = runner.run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])
            return r.out.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
        }
        switch located {
        case .notFound: return .failed("Couldn't find the terminal this session runs in")
        case .ambiguous: return .failed("Several terminals match this session, so Hubbub won't guess")
        case .found(let tty, _):
            var firstFailure: String?
            let outcomes: [() -> ChannelOutcome] = [
                { TmuxChannel(runner: runner, env: env).deliver(keys, tty: tty) },
                { AppleScriptChannel(app: .iterm, runner: runner, env: env).deliver(keys, tty: tty) },
                { AppleScriptChannel(app: .terminal, runner: runner, env: env).deliver(keys, tty: tty) },
            ]
            var notes: [String] = []
            for attempt in outcomes {
                switch attempt() {
                case .sent(let via): return .sent(via: via)
                case .failed(let m): firstFailure = firstFailure ?? m
                case .notApplicable(let m): notes.append(m)
                }
            }
            return .failed(firstFailure ?? "Hubbub can type into tmux, iTerm2 or Terminal.app; this session isn't in one of them (\(notes.last ?? "no match"))")
        }
    }
}
