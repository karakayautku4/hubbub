import AppKit
import CryptoKit
import Foundation
import SwiftUI

// MARK: - Snapshot format (version 1)
//
// Each machine writes ONE file `hubbub-snapshot-<machineId>.json` into a folder the user picked and reads the
// files other machines wrote there. Hubbub itself does no networking: whatever syncs the folder (iCloud Drive,
// Dropbox, a network share) does the transport. Snapshots hold metadata only: no prompts, messages, file
// contents, working directories or credentials. Session ids are salted hashes, titles are opt-in.

struct SyncSession: Codable, Equatable {
    var id: String
    var provider: String
    var title: String?
    var state: String
    var inputTokens: Int?
    var outputTokens: Int?
    var startedAt: Date?
    var lastEvent: Date
}

struct SyncSnapshot: Codable, Equatable {
    var version = 1
    var machineId: String
    var machineName: String
    var generatedAt: Date
    var sessions: [SyncSession]
}

struct SyncOptions: Equatable {
    var shareTitles = false
    var shareTokens = true
    var onlyActive = false
}

enum SyncCodec {
    static let filePrefix = "hubbub-snapshot-"
    static let maxFileBytes = 1_000_000
    static let maxSessions = 100
    static let staleAfter: TimeInterval = 7 * 86400

    static func fileName(_ machineId: String) -> String { "\(filePrefix)\(machineId).json" }

    static func hashID(_ id: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + "|" + id).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// Redaction happens here, before anything is written: fields that are not opted in never reach the file.
    static func makeSnapshot(_ sessions: [SessionInfo], options: SyncOptions, machineId: String, machineName: String,
                             now: Date = Date()) -> SyncSnapshot {
        let picked = sessions.filter { !options.onlyActive || $0.state == .working }.prefix(maxSessions)
        let out = picked.map { s in
            SyncSession(id: hashID(s.id, salt: machineId), provider: s.provider,
                        title: options.shareTitles ? clean(s.name, 80) : nil,
                        state: s.state.rawValue,
                        inputTokens: options.shareTokens ? s.inputTokens : nil,
                        outputTokens: options.shareTokens ? s.outputTokens : nil,
                        startedAt: s.startedAt, lastEvent: s.lastEvent)
        }
        return SyncSnapshot(machineId: machineId, machineName: clean(machineName, 40), generatedAt: now, sessions: out)
    }

    static func clean(_ s: String, _ limit: Int) -> String {
        String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init).prefix(limit))
            .trimmingCharacters(in: .whitespaces)
    }

    static func encode(_ s: SyncSnapshot) -> Data? {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(s)
    }

    /// Remote files are untrusted input: size-capped, clamped and stripped of control characters.
    static func decode(_ data: Data, now: Date = Date()) -> SyncSnapshot? {
        guard data.count <= maxFileBytes else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard var s = try? d.decode(SyncSnapshot.self, from: data), s.version == 1,
              now.timeIntervalSince(s.generatedAt) < staleAfter else { return nil }
        s.machineId = String(s.machineId.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(40))
        s.machineName = clean(s.machineName, 40)
        guard !s.machineId.isEmpty, !s.machineName.isEmpty else { return nil }
        s.sessions = s.sessions.prefix(maxSessions).map { x in
            var x = x
            x.id = String(x.id.filter { $0.isLetter || $0.isNumber }.prefix(40))
            x.provider = String(x.provider.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(20))
            x.title = x.title.map { clean($0, 80) }.flatMap { $0.isEmpty ? nil : $0 }
            if !["working", "idle", "offline"].contains(x.state) { x.state = "idle" }
            x.inputTokens = x.inputTokens.map { max(0, $0) }
            x.outputTokens = x.outputTokens.map { max(0, $0) }
            return x
        }
        return s
    }

    static func records(from s: SyncSnapshot, providerName: (String) -> String = { $0 }) -> [SessionRecord] {
        s.sessions.map { x in
            var r = SessionRecord(id: "\(s.machineId)|\(x.id)", provider: x.provider,
                                  name: x.title ?? "\(providerName(x.provider)) session \(x.id.prefix(4))",
                                  state: x.state, tokens: 0, lastEvent: x.lastEvent, machine: s.machineName)
            r.inputTokens = x.inputTokens ?? 0; r.outputTokens = x.outputTokens ?? 0; r.startedAt = x.startedAt
            return r
        }
    }

    // MARK: Folder IO

    @discardableResult
    static func write(_ s: SyncSnapshot, to folder: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue,
              let data = encode(s) else { return false }
        return (try? data.write(to: folder.appendingPathComponent(fileName(s.machineId)), options: .atomic)) != nil
    }

    static func readOthers(in folder: URL, excluding machineId: String, now: Date = Date()) -> [SyncSnapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(filePrefix) && $0.hasSuffix(".json") && $0 != fileName(machineId) }.sorted().compactMap { n in
            let url = folder.appendingPathComponent(n)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size <= maxFileBytes,
                  let data = try? Data(contentsOf: url), let s = decode(data, now: now), s.machineId != machineId else { return nil }
            return s
        }
    }
}

// MARK: - Runtime

@MainActor
final class TeamSync: ObservableObject {
    static let shared = TeamSync()
    static let enabledKey = "sync.enabled", folderKey = "sync.folder", nameKey = "sync.machineName"
    static let titlesKey = "sync.shareTitles", tokensKey = "sync.shareTokens", activeKey = "sync.onlyActive"
    private static let idKey = "sync.machineId"

    @Published private(set) var remote: [SessionRecord] = []
    @Published private(set) var machines: [String] = []
    @Published private(set) var status = ""
    private var latest: [SessionInfo] = []
    private var lastWrite = Date.distantPast
    private var lastWritten: SyncSnapshot?
    private var timer: Timer?
    private var busy = false

    private var d: UserDefaults { .standard }
    var enabled: Bool { d.bool(forKey: Self.enabledKey) }
    var folder: URL? { d.string(forKey: Self.folderKey).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) } }
    var machineId: String {
        if let id = d.string(forKey: Self.idKey) { return id }
        let id = UUID().uuidString.lowercased(); d.set(id, forKey: Self.idKey); return id
    }
    var machineName: String {
        let n = SyncCodec.clean(d.string(forKey: Self.nameKey) ?? "", 40)
        return n.isEmpty ? Self.defaultName : n
    }
    static var defaultName: String { Host.current().localizedName ?? "This Mac" }
    var options: SyncOptions {
        SyncOptions(shareTitles: d.bool(forKey: Self.titlesKey),
                    shareTokens: d.object(forKey: Self.tokensKey) as? Bool ?? true,
                    onlyActive: d.bool(forKey: Self.activeKey))
    }

    /// Called after every session scan. Writes at most every 30 seconds and only when something changed.
    func publish(_ sessions: [SessionInfo], now: Date = Date()) {
        latest = sessions
        guard enabled, let folder else { return }
        armTimer()
        guard now.timeIntervalSince(lastWrite) >= 30 else { return }
        var snap = SyncCodec.makeSnapshot(sessions, options: options, machineId: machineId, machineName: machineName, now: now)
        var cmp = snap; cmp.generatedAt = .distantPast
        var prev = lastWritten; prev?.generatedAt = .distantPast
        guard cmp != prev || now.timeIntervalSince(lastWrite) > 600 else { return }
        lastWrite = now
        snap.generatedAt = now
        lastWritten = snap
        let s = snap
        Task.detached(priority: .utility) {
            let ok = SyncCodec.write(s, to: folder)
            await MainActor.run { TeamSync.shared.status = ok ? "Shared \(s.sessions.count) session\(s.sessions.count == 1 ? "" : "s") as \(s.machineName)" : "Could not write to the sync folder" }
        }
    }

    func readNow() {
        guard enabled, let folder, !busy else { if !enabled { clear() }; return }
        busy = true
        let id = machineId
        Task.detached(priority: .utility) {
            let snaps = SyncCodec.readOthers(in: folder, excluding: id)
            let recs = snaps.flatMap { SyncCodec.records(from: $0) { ProviderRegistry.shared.name(for: $0) } }
            await MainActor.run {
                let t = TeamSync.shared
                t.busy = false
                t.remote = recs
                t.machines = snaps.map(\.machineName)
            }
        }
    }

    func settingsChanged() {
        lastWrite = .distantPast; lastWritten = nil
        if enabled { publish(latest); readNow() } else { clear(); timer?.invalidate(); timer = nil }
    }

    /// Stops sharing for good: removes this machine's own snapshot from the folder (never touches other files).
    func deleteMySnapshot() {
        if let folder { try? FileManager.default.removeItem(at: folder.appendingPathComponent(SyncCodec.fileName(machineId))) }
        status = "Your snapshot was removed from the folder"
    }

    private func clear() { remote = []; machines = [] }

    private func armTimer() {
        guard timer == nil else { return }
        readNow()
        let t = Timer(timeInterval: 30, repeats: true) { _ in Task { @MainActor in TeamSync.shared.readNow() } }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - Views

/// Sessions of other machines, shown under the local quota strips on the Live page.
struct RemoteSessionsStrip: View {
    @ObservedObject private var sync = TeamSync.shared

    var body: some View {
        let live = sync.remote.sorted { $0.lastEvent > $1.lastEvent }.prefix(6)
        if sync.enabled, !live.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("OTHER MACHINES").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                ForEach(Array(live)) { r in
                    HStack(spacing: 6) {
                        Image(systemName: r.state == "working" ? "play.fill" : "moon.fill").font(.system(size: 8))
                            .foregroundStyle(r.state == "working" ? Color.green : Color.secondary)
                        ProviderBadge(provider: r.provider)
                        Text(r.name).font(.caption).lineLimit(1)
                        Chip(text: r.machine ?? "", color: .purple)
                        Spacer(minLength: 0)
                        Text(min(r.lastEvent, Date()).formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(r.name) on \(r.machine ?? "another machine"), \(r.state)")
                }
            }
        }
    }
}

struct SyncSettingsView: View {
    @AppStorage(TeamSync.enabledKey) private var enabled = false
    @AppStorage(TeamSync.folderKey) private var folder = ""
    @AppStorage(TeamSync.nameKey) private var name = ""
    @AppStorage(TeamSync.titlesKey) private var titles = false
    @AppStorage(TeamSync.tokensKey) private var tokens = true
    @AppStorage(TeamSync.activeKey) private var active = false
    @ObservedObject private var sync = TeamSync.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Share a summary with my other Macs", isOn: $enabled.onChange { sync.settingsChanged() }).toggleStyle(.switch).controlSize(.small)
            Text("Each Mac writes one small file into a folder you choose (iCloud Drive, Dropbox, a share) and reads the others. Nothing goes over the network. Prompts, messages, file contents, paths and credentials are never shared.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(folder.isEmpty ? "No folder chosen" : (folder as NSString).abbreviatingWithTildeInPath)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(folder)
                Spacer()
                Button("Choose folder…") { chooseFolder() }.controlSize(.small)
            }
            HStack {
                Text("Machine name").font(.caption)
                TextField(TeamSync.defaultName, text: $name, onCommit: { sync.settingsChanged() })
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 180)
            }
            Divider()
            Toggle("Share session titles", isOn: $titles.onChange { sync.settingsChanged() }).toggleStyle(.switch).controlSize(.small)
            Toggle("Share token counts", isOn: $tokens.onChange { sync.settingsChanged() }).toggleStyle(.switch).controlSize(.small)
            Toggle("Only sessions working right now", isOn: $active.onChange { sync.settingsChanged() }).toggleStyle(.switch).controlSize(.small)
            HStack {
                Button("Stop sharing and delete my file") { enabled = false; sync.deleteMySnapshot(); sync.settingsChanged() }
                    .controlSize(.small).disabled(folder.isEmpty)
                Spacer()
            }
            if enabled {
                Divider()
                Text(folder.isEmpty ? "Choose a folder to start sharing." : sync.status.isEmpty ? "Waiting for the next session update…" : sync.status).font(.caption2)
                Text(sync.machines.isEmpty ? "No other machines found yet." : "Seen: " + sync.machines.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                Button("Refresh now") { sync.readNow() }.controlSize(.small)
            }
        }
    }

    private func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true; p.allowsMultipleSelection = false
        p.prompt = "Choose"; p.message = "Pick a folder that is synced between your machines. Hubbub writes one small summary file there."
        if HotkeyManager.runPanel(p) == .OK, let url = p.url { folder = url.path; sync.settingsChanged() }
    }
}

private extension Binding {
    func onChange(_ f: @escaping () -> Void) -> Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0; DispatchQueue.main.async(execute: f) })
    }
}
