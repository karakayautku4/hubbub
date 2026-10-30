import Foundation
import SQLite3

/// Cursor IDE agent/composer sessions. Structure only: `globalStorage/state.vscdb` has `composerHeaders`
/// (id, workspaceId, createdAt, lastUpdatedAt, isArchived, isSubagent) and `cursorDiskKV` with
/// `composerData:<id>` (model, bubble header list) and `bubbleId:<composer>:<bubble>` (tool name/status, token counts).
/// Message text is never read into memory beyond the JSON parse and is never stored.
struct CursorProvider: AgentProvider {
    let id = "cursor"
    let displayName = "Cursor"
    let symbol = "cursorarrow.rays"
    let dataHint = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

    private static let cache = ProviderKit.OfflineCache()
    private static let bubbleLimit = 24

    private var userDir: URL {
        ProviderKit.home.appendingPathComponent("Library/Application Support/Cursor/User")
    }
    private var dbURL: URL { userDir.appendingPathComponent("globalStorage/state.vscdb") }

    var isAvailable: Bool { FileManager.default.fileExists(atPath: dbURL.path) }

    func scan() -> [SessionInfo] {
        let walMod = ProviderKit.modDate(URL(fileURLWithPath: dbURL.path + "-wal"))
        let dbMod = max(ProviderKit.modDate(dbURL) ?? .distantPast, walMod ?? .distantPast)
        guard dbMod > Date().addingTimeInterval(-ProviderKit.recentWindow), let db = Self.open(dbURL) else { return [] }
        defer { sqlite3_close(db) }

        let cutoffMs = Int64(Date().addingTimeInterval(-ProviderKit.recentWindow).timeIntervalSince1970 * 1000)
        var headers: [(id: String, ws: String, created: Int64, updated: Int64)] = []
        Self.query(db, """
            SELECT composerId, COALESCE(workspaceId,''), COALESCE(createdAt,0), COALESCE(lastUpdatedAt, createdAt, 0)
            FROM composerHeaders WHERE COALESCE(isArchived,0)=0 AND COALESCE(isSubagent,0)=0 AND COALESCE(lastUpdatedAt, createdAt, 0)>=?
            ORDER BY COALESCE(lastUpdatedAt, createdAt, 0) DESC LIMIT \(ProviderKit.perProviderLimit)
            """, int: cutoffMs) { st in
            headers.append((Self.text(st, 0), Self.text(st, 1), sqlite3_column_int64(st, 2), sqlite3_column_int64(st, 3)))
        }

        return headers.compactMap { h in
            let mod = Date(timeIntervalSince1970: Double(h.updated) / 1000)
            if let hit = Self.cache.get("cursor:" + h.id, mod) { return hit }
            let composer = Self.value(db, "composerData:" + h.id).flatMap(Self.object)
            var bubbleIDs: [String] = []
            for e in (composer?["fullConversationHeadersOnly"] as? [[String: Any]] ?? []).suffix(Self.bubbleLimit) {
                if let b = e["bubbleId"] as? String { bubbleIDs.append(b) }
            }
            let bubbles = bubbleIDs.compactMap { b in Self.value(db, "bubbleId:\(h.id):\(b)").flatMap(Self.object) }
            var info = Self.parse(composer: composer, bubbles: bubbles, id: h.id, created: Date(timeIntervalSince1970: Double(h.created) / 1000),
                                  modified: mod, cwd: Self.workspaceFolder(userDir, h.ws))
            info.name = info.cwd.isEmpty ? "Cursor #\(h.id.prefix(4))" : "\(ProviderKit.folder(info.cwd)) #\(h.id.prefix(4))"
            Self.cache.put("cursor:" + h.id, mod, info)
            return info
        }
    }

    /// `composer`/`bubbles` are the decoded JSON values; unknown or missing keys are tolerated.
    static func parse(composer: [String: Any]?, bubbles: [[String: Any]], id: String, created: Date?, modified: Date, cwd: String = "") -> SessionInfo {
        var b = SessionBuilder(provider: "cursor", rawID: id, modified: modified)
        b.created = created
        b.cwd = cwd
        if let m = (composer?["modelConfig"] as? [String: Any])?["modelName"] as? String, m != "default" { b.model = m }
        for (i, bub) in bubbles.enumerated() {
            if let tf = bub["toolFormerData"] as? [String: Any], let name = tf["name"] as? String {
                let cid = (tf["toolCallId"] as? String) ?? "b\(i)"
                b.toolStart(id: cid, tool: mapTool(name), detail: "", at: modified)
                switch (tf["status"] as? String)?.lowercased() ?? "" {
                case "completed", "success": b.toolEnd(id: cid, ok: true, at: modified)
                case "error", "failed", "cancelled", "rejected": b.toolEnd(id: cid, ok: false, at: modified, error: "Tool failed")
                default: break
                }
            }
            if let t = bub["tokenCount"] as? [String: Any] {
                b.inputTokens += t["inputTokens"] as? Int ?? 0
                b.outputTokens += t["outputTokens"] as? Int ?? 0
            }
        }
        // Cursor only exposes the last update time, so a still-running tool older than the window is not trusted.
        return b.build()
    }

    /// Cursor tool names (read_file, edit_file, run_terminal_cmd, codebase_search, ...) -> names `Theme.toolKind` understands.
    static func mapTool(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("terminal") || n.contains("shell") || n.contains("command") { return "bash" }
        if n.contains("edit") || n.contains("write") || n.contains("delete") || n.contains("apply") || n.contains("patch") { return "edit" }
        if n.contains("grep") || n.contains("search") { return n.contains("web") ? "web_search" : "grep" }
        if n.contains("read") || n.contains("list") || n.contains("glob") || n.contains("file_search") { return "view" }
        return name
    }

    // MARK: SQLite (read-only)

    /// Opens read-only; when the live DB is locked, retries on a copy in the user caches directory.
    private static func open(_ url: URL) -> OpaquePointer? {
        func tryOpen(_ path: String) -> OpaquePointer? {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { sqlite3_close(db); return nil }
            sqlite3_busy_timeout(db, 300)
            var st: OpaquePointer?
            let ok = sqlite3_prepare_v2(db, "SELECT 1 FROM composerHeaders LIMIT 1", -1, &st, nil) == SQLITE_OK
                && [SQLITE_ROW, SQLITE_DONE].contains(sqlite3_step(st))
            sqlite3_finalize(st)
            if ok { return db }
            sqlite3_close(db)
            return nil
        }
        if let db = tryOpen(url.path) { return db }
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("Hubbub/cursor-copy")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = dir.appendingPathComponent("state.vscdb")
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: copy.path + suffix)
            try? fm.copyItem(atPath: url.path + suffix, toPath: copy.path + suffix)
        }
        return tryOpen(copy.path)
    }

    private static func text(_ st: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(st, col).map { String(cString: $0) } ?? ""
    }

    private static func query(_ db: OpaquePointer, _ sql: String, int: Int64? = nil, row: (OpaquePointer) -> Void) {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else { sqlite3_finalize(st); return }
        defer { sqlite3_finalize(st) }
        if let int { sqlite3_bind_int64(st, 1, int) }
        while sqlite3_step(st) == SQLITE_ROW { row(st) }
    }

    /// Value of a cursorDiskKV key (stored as TEXT or BLOB).
    private static func value(_ db: OpaquePointer, _ key: String) -> Data? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM cursorDiskKV WHERE key=?", -1, &st, nil) == SQLITE_OK, let st else { sqlite3_finalize(st); return nil }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(st) == SQLITE_ROW, let p = sqlite3_column_blob(st, 0) else { return nil }
        let n = Int(sqlite3_column_bytes(st, 0))
        guard n > 0, n < 8_000_000 else { return nil }
        return Data(bytes: p, count: n)
    }

    private static func object(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }

    /// workspaceStorage/<workspaceId>/workspace.json -> {"folder":"file:///path"}
    private static func workspaceFolder(_ userDir: URL, _ ws: String) -> String {
        guard !ws.isEmpty, !ws.contains("/"),
              let d = try? Data(contentsOf: userDir.appendingPathComponent("workspaceStorage/\(ws)/workspace.json")),
              let s = object(d)?["folder"] as? String, let u = URL(string: s), u.isFileURL else { return "" }
        return u.path
    }
}
