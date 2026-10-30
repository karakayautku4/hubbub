import SwiftUI
import AppKit

/// Details for one session: four collapsible sections. Live sessions show everything; stored records are read-only
/// (no tool calls / sub-agents / actions that need a running session).
struct SessionDetailView: View {
    private let live: SessionInfo?
    private let record: SessionRecord
    private let attention: AttentionLevel
    let onClose: () -> Void
    @State private var copied: String?
    @State private var open: Set<Section> = [.session]
    @ObservedObject private var library = SessionLibrary.shared

    private enum Section: String, CaseIterable { case session = "Session", cost = "Tokens & cost", activity = "Activity", organise = "Organise" }

    init(session: SessionInfo, attention: AttentionLevel, onClose: @escaping () -> Void) {
        live = session; record = SessionRecord(session); self.attention = attention; self.onClose = onClose
    }

    init(record: SessionRecord, onClose: @escaping () -> Void) {
        live = nil; self.record = record; attention = .none; self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            header
            ForEach(Section.allCases.filter { $0 != .activity || live != nil }, id: \.self) { sec in
                DisclosureGroup(isExpanded: Binding(get: { open.contains(sec) }, set: { if $0 { open.insert(sec) } else { open.remove(sec) } })) {
                    if open.contains(sec) { content(sec).padding(.top, Space.xs).frame(maxWidth: .infinity, alignment: .leading) }
                } label: { Text(sec.rawValue).font(HubFont.title) }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: Space.sm) {
            ProviderBadge(provider: record.provider)
            Text(record.name).font(HubFont.title).lineLimit(1).truncationMode(.tail)
            if attention != .none {
                Text(attention == .stuck ? "Stuck" : "Failed")
                    .font(HubFont.caption.bold()).padding(.horizontal, Space.sm).padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.85))).foregroundStyle(.white)
                    .accessibilityLabel(attention == .stuck ? "Session stuck" : "Session failed")
            }
            Spacer(minLength: Space.xs)
            if let c = copied { Text(c).font(HubFont.caption).foregroundStyle(.secondary).lineLimit(1) }
            if let s = live {
                Button("Open in Terminal") { SessionActions.openTerminal(s) { flash($0) } }.buttonStyle(.borderedProminent).controlSize(.small)
                Menu {
                    Button("Open in editor") { SessionActions.openEditor(s) { flash($0) } }
                    Button("Reveal in Finder") { SessionActions.reveal(s) { flash($0) } }
                    Button("Copy session ID") { copy(s.id, "ID copied ✓") }
                    if let cmd = s.resumeCommand { Button("Copy resume command") { copy(cmd, "Command copied ✓") } }
                    Divider()
                    Button("Save summary as Markdown…") { Task { flash(await SessionExport.saveMarkdown(s)) } }
                    Button("Copy as Markdown") { Task { flash(await SessionExport.copyMarkdown(s)) } }
                    Button("Save stage snapshot (PNG)…") { flash(SessionExport.saveStagePNG(s)) }
                    Button("Save share card (PNG)…") { flash(SessionExport.saveShareCard(s)) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("More actions: editor, Finder, copy ID, export")
                .accessibilityLabel("More actions")
            } else {
                Button { copy(record.id, "ID copied ✓") } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy session ID").accessibilityLabel("Copy session ID")
            }
        }
    }

    // MARK: sections

    @ViewBuilder private func content(_ sec: Section) -> some View {
        switch sec {
        case .session: sessionSection
        case .cost: costSection
        case .activity: activitySection
        case .organise: SessionOrganizer(record: record, library: library).id(record.id)
        }
    }

    private var sessionSection: some View {
        Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
            row("Folder", record.cwd.isEmpty ? Fmt.none : record.cwd, truncation: .middle)
            if !record.branch.isEmpty { row("Branch", record.branch) }
            row("Model", record.model.isEmpty ? Fmt.none : record.model)
            row("Provider", ProviderRegistry.shared.name(for: record.provider))
            if let m = record.machine { row("Machine", m) }
            row("Started", record.startedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? Fmt.none)
            row("Duration", record.activeDuration.map { Fmt.duration($0) } ?? Fmt.none)
            row("Last event", "\(Fmt.relative(record.lastEvent)) · \(record.state.capitalized)")
            if let s = live { row("Approval", s.waitingApproval ? "Waiting for your answer" : "None pending") }
        }
    }

    private var costSection: some View {
        let cost = record.costDisplay
        return VStack(alignment: .leading, spacing: Space.sm) {
            Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
                row("Input", Fmt.tokens(record.inputTokens))
                row("Output", Fmt.tokens(record.outputTokens))
                row("Total", Fmt.tokens(record.inputTokens + record.outputTokens))
                if let s = live, s.contextLimit > 0 {
                    row("Context", "\(Fmt.percent(s.contextFraction)) · \(Fmt.pair(s.contextTokens, s.contextLimit))")
                }
                row("Cost", [cost.value, cost.sub].compactMap { $0 }.joined(separator: " · "), help: cost.tooltip)
            }
            if live != nil {
                BudgetChip(sessionID: record.id)
                ProjectionLine()
            }
        }
    }

    @ViewBuilder private var activitySection: some View {
        if let s = live {
            VStack(alignment: .leading, spacing: Space.sm) {
                Grid(alignment: .leading, horizontalSpacing: Space.md, verticalSpacing: Space.xs) {
                    row("Success", s.toolCalls > 0 ? Fmt.percent(s.successRate) : Fmt.none)
                    row("Tool calls", "\(s.toolCalls)")
                    row("Failures", "\(s.failures)")
                }
                if let err = s.lastError {
                    HStack(alignment: .top) {
                        Text(err).font(HubFont.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled).help(err)
                        Spacer(minLength: Space.xs)
                        Button { copy(err, "Error copied ✓") } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy error").accessibilityLabel("Copy error")
                    }
                }
                if !s.subagents.isEmpty {
                    Text("Sub-agents").font(HubFont.caption.bold()).foregroundStyle(.secondary)
                    ForEach(s.subagents) { a in
                        HStack(spacing: Space.xs) {
                            Circle().fill(a.busy ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(a.displayName).font(HubFont.caption).lineLimit(1)
                            Spacer(minLength: Space.xs)
                            Text([a.contextLimit > 0 ? Fmt.percent(a.contextFraction) : nil, a.costCredits > 0 ? Fmt.creditsShort(a.costCredits) : nil]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(HubFont.captionDigits).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .help("\(a.displayName) · \(a.model)")
                    }
                }
                Text("Recent tool calls").font(HubFont.caption.bold()).foregroundStyle(.secondary)
                if s.recentCalls.isEmpty { Text("Nothing yet").font(HubFont.caption).foregroundStyle(.secondary) }
                ForEach(s.recentCalls.suffix(15).reversed()) { c in
                    HStack(spacing: Space.xs) {
                        Image(systemName: icon(c.status)).foregroundStyle(color(c.status)).font(HubFont.caption)
                            .accessibilityLabel(label(c.status))
                        Text("\(c.tool)\(c.detail.isEmpty ? "" : " — \(c.detail)")")
                            .font(HubFont.caption).lineLimit(1).truncationMode(.tail).help("\(c.tool) \(c.detail)")
                        Spacer(minLength: Space.xs)
                        Text(c.time, style: .time).font(HubFont.captionDigits).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func flash(_ msg: String) {
        copied = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if copied == msg { copied = nil } }
    }

    private func copy(_ text: String, _ note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(note)
    }

    private func row(_ k: String, _ v: String, truncation: Text.TruncationMode = .tail, help: String? = nil) -> some View {
        GridRow {
            Text(k).font(HubFont.caption).foregroundStyle(.secondary)
            Text(v).font(HubFont.captionDigits).lineLimit(1).truncationMode(truncation).textSelection(.enabled).help(help ?? v)
        }
    }

    private func icon(_ s: CallStatus) -> String {
        switch s { case .running: "circle.dotted"; case .ok: "checkmark.circle.fill"; case .failed: "xmark.circle.fill" }
    }

    private func label(_ s: CallStatus) -> String {
        switch s { case .running: "Running"; case .ok: "Succeeded"; case .failed: "Failed" }
    }

    private func color(_ s: CallStatus) -> Color {
        switch s { case .running: .orange; case .ok: .green; case .failed: .red }
    }
}

/// Favourite, tags and note for one session.
struct SessionOrganizer: View {
    let record: SessionRecord
    @ObservedObject var library: SessionLibrary
    @State private var tagText = ""
    @State private var noteText = ""
    @State private var loaded = false

    var body: some View {
        let fav = library.isFavorite(record.id)
        VStack(alignment: .leading, spacing: Space.sm) {
            if record.machine == nil {
                Toggle(isOn: Binding(get: { fav }, set: { _ in library.toggleFavorite(record.id) })) {
                    Label("Favourite", systemImage: fav ? "star.fill" : "star").font(HubFont.body)
                }
                TextField("Tags, comma separated", text: $tagText, onCommit: commit).textFieldStyle(.roundedBorder).font(HubFont.body)
                TextField("Note", text: $noteText, onCommit: commit).textFieldStyle(.roundedBorder).font(HubFont.body)
            } else {
                Text("Synced from another machine — organise it there.").font(HubFont.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            tagText = library.tags(record.id).joined(separator: ", "); noteText = library.note(record.id)
        }
        .onDisappear { if loaded, record.machine == nil { commit() } }
    }

    private func commit() {
        library.setTags(record.id, SessionSearch.parseTags(tagText))
        library.setNote(record.id, noteText)
    }
}

enum SessionActions {
    static func dirExists(_ s: SessionInfo) -> Bool {
        var isDir: ObjCBool = false
        return !s.cwd.isEmpty && FileManager.default.fileExists(atPath: s.cwd, isDirectory: &isDir) && isDir.boolValue
    }

    @MainActor static func openTerminal(_ s: SessionInfo, _ report: @escaping (String) -> Void) {
        let ctx = ReplyCenter.context(for: s)
        DispatchQueue.global(qos: .userInitiated).async {
            let r = TerminalFocus().focus(ctx)
            DispatchQueue.main.async {
                if let app = r.app { report("Showing the session in \(app)") }
                else { openFolderInTerminal(s, reason: r.reason, report) }
            }
        }
    }

    private static func openFolderInTerminal(_ s: SessionInfo, reason: String?, _ report: @escaping (String) -> Void) {
        guard dirExists(s) else { report(reason ?? "Folder not found"); return }
        var note = "Opened Terminal"
        if let cmd = s.resumeCommand {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
            note = "Resume command copied ✓ — paste it in Terminal"
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: s.cwd)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration()) { _, err in
            DispatchQueue.main.async { report(err.map { "Could not open Terminal: \($0.localizedDescription)" } ?? note) }
        }
    }

    static func openEditor(_ s: SessionInfo, _ report: @escaping (String) -> Void) {
        guard dirExists(s) else { report("Folder not found"); return }
        let apps = ["Visual Studio Code", "Visual Studio Code - Insiders", "Cursor"]
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        guard let app = apps.first(where: { a in dirs.contains { FileManager.default.fileExists(atPath: "\($0)/\(a).app") } }) else {
            report("No editor found (VS Code, VS Code Insiders or Cursor)"); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", app, s.cwd]
        let err = Pipe()
        p.standardError = err
        p.terminationHandler = { proc in
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async { report(proc.terminationStatus == 0 ? "Opened in \(app)" : "Could not open \(app): \(msg)") }
        }
        do { try p.run() } catch { report("Could not open \(app): \(error.localizedDescription)") }
    }

    static func reveal(_ s: SessionInfo, _ report: @escaping (String) -> Void) {
        guard dirExists(s) else { report("Folder not found"); return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cwd)])
    }
}
