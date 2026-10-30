import Foundation
import SwiftUI

/// One session as remembered for search, favorites and comparison. Contains metadata only, never prompts or content.
struct SessionRecord: Codable, Identifiable, Equatable {
    var id: String
    var provider: String
    var name: String
    var cwd: String
    var branch: String = ""
    var model: String = ""
    var state: String = "idle"
    var failed = false
    var inputTokens = 0
    var outputTokens = 0
    var credits = 0.0
    var startedAt: Date?
    var lastEvent: Date
    /// nil = this machine; otherwise the machine name of a synced snapshot.
    var machine: String?
    /// Per-day share of the lifetime totals ("yyyy-MM-dd"); nil for records from before this was tracked.
    var days: [String: DayUsage]?
    /// Active seconds (idle gaps capped); nil for older records.
    var active: Double?

    init(_ s: SessionInfo) {
        id = s.id; provider = s.provider; name = s.name; cwd = s.cwd; branch = s.branch; model = s.model
        state = s.state.rawValue; failed = s.lastFailureAt != nil
        inputTokens = s.inputTokens; outputTokens = s.outputTokens; credits = s.costCredits
        startedAt = s.startedAt; lastEvent = s.lastEvent
        days = s.dayUsage.isEmpty ? nil : s.dayUsage; active = s.activeSeconds
    }

    init(id: String, provider: String, name: String, cwd: String = "", model: String = "", state: String = "idle",
         tokens: Int = 0, credits: Double = 0, lastEvent: Date, machine: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.cwd = cwd; self.model = model
        self.state = state; self.inputTokens = tokens; self.credits = credits; self.lastEvent = lastEvent; self.machine = machine
    }

    var project: String {
        let f = (cwd as NSString).lastPathComponent
        return f.isEmpty || f == "/" ? "No folder" : f
    }
}

struct SessionMeta: Codable, Equatable {
    var favorites: Set<String> = []
    var tags: [String: [String]] = [:]
    var notes: [String: String] = [:]
}

enum DateRange: String, CaseIterable, Identifiable {
    case all, today, week, month
    var id: String { rawValue }
    var title: String { ["all": "Any time", "today": "Today", "week": "7 days", "month": "30 days"][rawValue] ?? rawValue }
    func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .all: nil
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        }
    }
}

enum StatusFilter: String, CaseIterable, Identifiable {
    case any, working, idle, offline, failed
    var id: String { rawValue }
    var title: String { rawValue == "any" ? "Any status" : rawValue.capitalized }
}

struct SessionFilter: Equatable {
    var query = ""
    var providers: Set<String> = []
    var range: DateRange = .all
    var status: StatusFilter = .any
    var favoritesOnly = false
    var tag: String?
}

/// Pure search/filter/group logic (self-tested).
enum SessionSearch {
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    static func matches(_ r: SessionRecord, meta: SessionMeta, filter f: SessionFilter, now: Date = Date(),
                        providerName: (String) -> String = { $0 }) -> Bool {
        if !f.providers.isEmpty, !f.providers.contains(r.provider) { return false }
        if let c = f.range.cutoff(now: now), r.lastEvent < c { return false }
        switch f.status {
        case .any: break
        case .failed: if !r.failed { return false }
        default: if r.state != f.status.rawValue { return false }
        }
        if f.favoritesOnly, !meta.favorites.contains(r.id) { return false }
        let tags = meta.tags[r.id] ?? []
        if let t = f.tag, !tags.contains(where: { fold($0) == fold(t) }) { return false }
        let hay = fold([r.name, r.cwd, r.branch, r.provider, providerName(r.provider), r.model, r.machine ?? "",
                        tags.joined(separator: " "), meta.notes[r.id] ?? ""].joined(separator: "\n"))
        for token in f.query.split(whereSeparator: \.isWhitespace) {
            if token.hasPrefix("#") {
                let t = fold(String(token.dropFirst()))
                if !t.isEmpty, !tags.contains(where: { fold($0).hasPrefix(t) }) { return false }
            } else if !hay.contains(fold(String(token))) { return false }
        }
        return true
    }

    /// Favorites first, then newest.
    static func apply(_ records: [SessionRecord], meta: SessionMeta, filter: SessionFilter, now: Date = Date(),
                      providerName: (String) -> String = { $0 }) -> [SessionRecord] {
        records.filter { matches($0, meta: meta, filter: filter, now: now, providerName: providerName) }.sorted {
            let a = meta.favorites.contains($0.id), b = meta.favorites.contains($1.id)
            return a != b ? a : $0.lastEvent > $1.lastEvent
        }
    }

    static func grouped(_ records: [SessionRecord], meta: SessionMeta) -> [(project: String, items: [SessionRecord])] {
        let groups = Dictionary(grouping: records, by: \.project)
        return groups.map { ($0.key, $0.value) }.sorted {
            let fa = $0.1.contains { meta.favorites.contains($0.id) }, fb = $1.1.contains { meta.favorites.contains($0.id) }
            if fa != fb { return fa }
            return ($0.1.map(\.lastEvent).max() ?? .distantPast) > ($1.1.map(\.lastEvent).max() ?? .distantPast)
        }
    }

    static func parseTags(_ text: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let clean = String(t.prefix(32))
            if !clean.isEmpty, seen.insert(fold(clean)).inserted { out.append(clean) }
        }
        return Array(out.prefix(12))
    }
}

/// Local index of sessions seen so far plus the user's favorites, tags and notes (Application Support JSON).
@MainActor
final class SessionLibrary: ObservableObject {
    static let shared = SessionLibrary()
    @Published private(set) var records: [SessionRecord] = []
    @Published private(set) var meta = SessionMeta()
    private var dirty = false
    private var lastSave = Date.distantPast
    private let dir: URL

    private static let maxRecords = 500
    private static let maxAge: TimeInterval = 180 * 86400
    private nonisolated static let ioQueue = DispatchQueue(label: "hubbub.session-library", qos: .utility)

    /// Blocks until queued writes are on disk (tests).
    nonisolated func flush() { Self.ioQueue.sync {} }

    init(dir: URL? = nil) {
        self.dir = dir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Hubbub")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: self.dir.appendingPathComponent("session-index.json")) { records = (try? dec.decode([SessionRecord].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: self.dir.appendingPathComponent("session-meta.json")) { meta = (try? dec.decode(SessionMeta.self, from: d)) ?? SessionMeta() }
    }

    func ingest(_ sessions: [SessionInfo], now: Date = Date()) {
        guard !sessions.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var changed = false
        for s in sessions {
            let r = SessionRecord.merged(prev: byID[s.id], with: s)
            if byID[r.id] != r { byID[r.id] = r; changed = true }
        }
        guard changed else { return }
        let keep = byID.values.filter { now.timeIntervalSince($0.lastEvent) < Self.maxAge || meta.favorites.contains($0.id) }
        records = Array(keep.sorted { $0.lastEvent > $1.lastEvent }.prefix(Self.maxRecords))
        dirty = true
        saveIfDue(now: now)
    }

    func isFavorite(_ id: String) -> Bool { meta.favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if !meta.favorites.insert(id).inserted { meta.favorites.remove(id) }
        saveMeta()
    }
    func tags(_ id: String) -> [String] { meta.tags[id] ?? [] }
    func note(_ id: String) -> String { meta.notes[id] ?? "" }
    func setTags(_ id: String, _ tags: [String]) { meta.tags[id] = tags.isEmpty ? nil : tags; saveMeta() }
    func setNote(_ id: String, _ text: String) { meta.notes[id] = text.isEmpty ? nil : String(text.prefix(500)); saveMeta() }
    var allTags: [String] { Array(Set(meta.tags.values.flatMap { $0 })).sorted() }

    private func saveIfDue(now: Date) {
        guard dirty, now.timeIntervalSince(lastSave) > 30 else { return }
        dirty = false; lastSave = now
        write(records, "session-index.json")
    }

    private func saveMeta() { write(meta, "session-meta.json") }

    private func write<T: Encodable>(_ value: T, _ file: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        let url = dir.appendingPathComponent(file), d = dir
        Self.ioQueue.async {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Single entry point called by SessionMonitor after each scan.
@MainActor
enum ProdFeatures {
    static func ingest(_ sessions: [SessionInfo]) {
        SessionLibrary.shared.ingest(sessions)
        TeamSync.shared.publish(sessions)
        CostProjectionCenter.shared.refresh()
    }
}

// MARK: - History browser (search, filters, day groups)

struct SessionBrowser: View {
    @ObservedObject private var library = SessionLibrary.shared
    @ObservedObject private var sync = TeamSync.shared
    @State private var filter = SessionFilter()
    @State private var grouped = false
    @State private var limit = SessionBrowser.pageSize
    @State private var detail: SessionRecord?
    @State private var hovered: String?
    @FocusState private var searchFocused: Bool

    static let pageSize = 40

    private var all: [SessionRecord] { library.records + sync.remote }
    private var results: [SessionRecord] {
        SessionSearch.apply(all, meta: library.meta, filter: filter) { ProviderRegistry.shared.name(for: $0) }.sorted { $0.lastEvent > $1.lastEvent }
    }
    private var providerIDs: [String] { Array(Set(all.map(\.provider))).sorted() }
    private var filtersActive: Bool { !filter.providers.isEmpty || filter.status != .any || filter.range != .all || filter.favoritesOnly || grouped }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search sessions", text: $filter.query).textFieldStyle(.plain).font(HubFont.body).focused($searchFocused)
                    if !filter.query.isEmpty {
                        Button { filter.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).accessibilityLabel("Clear search")
                    }
                }
                .padding(Space.sm).background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .background(Button("Search") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0))
                filterMenu
            }
            list
        }
        .padding(Space.sm)
        .onChange(of: filter) { _ in limit = Self.pageSize }
        .sheet(item: $detail) { r in
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack { Spacer(); Button("Done") { detail = nil }.keyboardShortcut(.cancelAction) }
                ScrollView { SessionDetailView(record: r) { detail = nil } }
            }
            .padding(Space.lg).frame(width: 440, height: 520)
        }
    }

    private var filterMenu: some View {
        Menu {
            Menu("Provider") {
                Button("All providers") { filter.providers = [] }
                ForEach(providerIDs, id: \.self) { id in
                    Toggle(ProviderRegistry.shared.name(for: id), isOn: Binding(
                        get: { filter.providers.contains(id) },
                        set: { if $0 { filter.providers.insert(id) } else { filter.providers.remove(id) } }))
                }
            }
            Picker("Status", selection: $filter.status) { ForEach(StatusFilter.allCases) { Text($0.title).tag($0) } }
            Picker("Range", selection: $filter.range) { ForEach(DateRange.allCases) { Text($0.title).tag($0) } }
            Toggle("Favourites only", isOn: $filter.favoritesOnly)
            Toggle("Group by project", isOn: $grouped)
            if filtersActive {
                Divider()
                Button("Clear filters") { filter = SessionFilter(query: filter.query); grouped = false }
            }
        } label: {
            Image(systemName: filtersActive ? "ellipsis.circle.fill" : "ellipsis.circle")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Filters").accessibilityLabel("Filters")
    }

    @ViewBuilder private var list: some View {
        let rows = results
        if rows.isEmpty {
            Text(all.isEmpty ? "No sessions yet — start an agent and it will show up here." : "No sessions match these filters.")
                .font(HubFont.body).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, Space.lg)
        } else {
            let shown = Array(rows.prefix(limit))
            LazyVStack(alignment: .leading, spacing: 0) {
                if grouped {
                    ForEach(SessionSearch.grouped(shown, meta: library.meta), id: \.project) { g in
                        header(g.project)
                        ForEach(g.items) { row($0) }
                    }
                } else {
                    ForEach(SessionBrowser.dayGroups(shown), id: \.day) { g in
                        header(Fmt.day(g.day))
                        ForEach(g.items) { row($0) }
                    }
                }
            }
            if rows.count > limit {
                Button("Show more") { limit += Self.pageSize }.buttonStyle(.borderless).font(HubFont.caption)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Records (newest first) split into calendar days.
    static func dayGroups(_ records: [SessionRecord], calendar: Calendar = .current) -> [(day: Date, items: [SessionRecord])] {
        var out: [(day: Date, items: [SessionRecord])] = []
        for r in records {
            let d = calendar.startOfDay(for: min(r.lastEvent, Date()))
            if let i = out.firstIndex(where: { $0.day == d }) { out[i].items.append(r) } else { out.append((d, [r])) }
        }
        return out
    }

    private func header(_ t: String) -> some View {
        Text(t).font(HubFont.caption.bold()).foregroundStyle(.secondary).padding(.top, Space.sm).padding(.bottom, Space.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ r: SessionRecord) -> some View {
        let fav = library.isFavorite(r.id)
        let cost = r.costDisplay
        let duration = r.activeDuration.map { Fmt.duration($0) } ?? Fmt.none
        return Button { open(r) } label: {
            HStack(spacing: Space.sm) {
                ProviderBadge(provider: r.provider)
                if fav { Image(systemName: "star.fill").foregroundStyle(.yellow).font(HubFont.caption).accessibilityHidden(true) }
                Text(r.name).font(HubFont.body).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: Space.sm)
                Text(duration).font(HubFont.bodyDigits).foregroundStyle(.secondary).frame(minWidth: 44, alignment: .trailing)
                Text(cost.short).font(HubFont.bodyDigits).foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
                    .help(cost.tooltip ?? "")
            }
            .frame(minHeight: Space.row).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6).fill(hovered == r.id ? Color.primary.opacity(0.06) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? r.id : (hovered == r.id ? nil : hovered) }
        .contextMenu {
            if r.machine == nil { Button(fav ? "Remove favourite" : "Add favourite") { library.toggleFavorite(r.id) } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.name), \(ProviderRegistry.shared.name(for: r.provider)), \(duration), \(cost.short)")
        .accessibilityHint("Opens details")
    }

    private func open(_ r: SessionRecord) {
        if AppModel.shared.monitor.sessions.contains(where: { $0.id == r.id }) { AppModel.shared.screen = .detail(r.id) } else { detail = r }
    }
}
