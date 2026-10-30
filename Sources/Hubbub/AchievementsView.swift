import SwiftUI

/// Full achievements screen: level header, cosmetics and badge grid with progress bars.
struct AchievementsView: View {
    @ObservedObject private var center = ProgressionCenter.shared

    var body: some View {
        let d = center.data
        VStack(alignment: .leading, spacing: 10) {
            if !center.enabled {
                HStack {
                    Text("Progression is turned off.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Turn on") { center.setEnabled(true) }.controlSize(.small)
                }
            }
            levelCard(d)
            Text("Achievements · \(d.unlocked.count) of \(BadgeCatalog.all.count)").font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BadgeCatalog.all) { badge($0, d) }
            }
            cosmetics
        }
        .padding(8)
    }

    private func levelCard(_ d: ProgressData) -> some View {
        let p = Levels.progress(xp: d.xp)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Level \(d.level) · \(center.title)").font(.headline)
                Spacer()
                Text("\(d.xp) XP").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(p.into), total: Double(max(1, p.span))).tint(.accentColor)
                .accessibilityLabel("Level progress").accessibilityValue("\(p.into) of \(p.span) XP")
            Text("\(p.span - p.into) XP to level \(d.level + 1) · \(d.tasks) tasks · \(d.sessionsCompleted) sessions · \(d.toolCalls) tool calls")
                .font(.caption).foregroundStyle(.secondary)
            Text("XP: 1 per successful tool call, 10 per finished task, 50 per completed session, 1 per 10k tokens, 100 per achievement.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func badge(_ def: BadgeDef, _ d: ProgressData) -> some View {
        let on = d.unlocked[def.id] != nil
        let pr = def.progress(d, Date(), .current)
        return HStack(alignment: .top, spacing: 8) {
            Text(def.icon).font(.title2).opacity(on ? 1 : 0.35).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(def.title).font(.caption.bold())
                Text(def.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if on {
                    Text("Unlocked").font(.caption2.bold()).foregroundStyle(.green)
                } else {
                    ProgressView(value: Double(min(pr.current, def.target)), total: Double(def.target)).controlSize(.small)
                    Text(pr.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .cardSurface(radius: 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.yellow.opacity(0.2) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Color.orange.opacity(0.6) : .clear, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(def.title), \(on ? "unlocked" : "locked, \(pr.label)")")
        .accessibilityHint(def.detail)
    }

    private var cosmetics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cosmetics").font(.subheadline.bold())
            ForEach(Progression.cosmetics) { c in
                let on = center.level >= c.level
                HStack(spacing: 6) {
                    Image(systemName: on ? "checkmark.circle.fill" : "lock.fill").foregroundStyle(on ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    Text(c.name).font(.caption)
                    Spacer()
                    Text(on ? "Unlocked" : "Level \(c.level)").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Worn by the captain on the stage (the star hat appears the next time the scene is rebuilt).")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Small top-of-popover toast; shows queued unlocks one at a time.
struct ProgressToastHost: View {
    @ObservedObject private var center = ProgressionCenter.shared

    var body: some View {
        ZStack(alignment: .top) {
            if let t = center.toasts.first {
                ToastCard(toast: t) { center.dismissToast(t.id) }
                    .id(t.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: center.toasts.first?.id)
        .allowsHitTesting(center.toasts.first != nil)
    }

    private struct ToastCard: View {
        let toast: ProgressToast
        let dismiss: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Text(toast.icon).font(.callout)
                VStack(alignment: .leading, spacing: 0) {
                    Text(toast.title).font(.caption.bold()).lineLimit(1)
                    Text(toast.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).font(.caption2).accessibilityLabel("Dismiss").help("Dismiss")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(A11y.panelFill()))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .task { try? await Task.sleep(nanoseconds: 3_500_000_000); dismiss() }
        }
    }
}

/// One-shot confetti: pieces fly out and fall once; no timers keep running afterwards.
struct ConfettiBurst: View {
    @State private var go = false
    private let pieces: [(dx: CGFloat, dy: CGFloat, rot: Double, color: Color, size: CGFloat)] = (0..<26).map { i in
        let colors: [Color] = [.red, .orange, .green, .blue, .purple, .pink, .yellow]
        let f = CGFloat(i)
        return (CGFloat(sin(f * 2.4)) * 150, 40 + CGFloat((i * 37) % 70), Double(i * 47 % 360), colors[i % colors.count], 4 + CGFloat(i % 3) * 2)
    }

    var body: some View {
        ZStack {
            ForEach(pieces.indices, id: \.self) { i in
                let p = pieces[i]
                RoundedRectangle(cornerRadius: 1).fill(p.color).frame(width: p.size, height: p.size * 1.6)
                    .rotationEffect(.degrees(go ? p.rot + 360 : p.rot))
                    .offset(x: go ? p.dx : 0, y: go ? p.dy : -4)
                    .opacity(go ? 0 : 1)
            }
        }
        .frame(width: 10, height: 10)
        .onAppear { withAnimation(.easeOut(duration: 1.6)) { go = true } }
    }
}

/// Settings › General › Progression.
struct ProgressionSettingsView: View {
    @ObservedObject private var center = ProgressionCenter.shared
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable progression")
                    Text("XP, levels, achievements and the scoreboard. Stored locally only.").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enable progression", isOn: Binding(get: { center.enabled }, set: { center.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(center.level) · \(center.title) — \(center.data.xp) XP")
                    Text("\(center.data.unlocked.count) of \(BadgeCatalog.all.count) achievements").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset progress…", role: .destructive) { confirmReset = true }.controlSize(.small)
            }
        }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { center.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("XP, level, achievements and scoreboard history will be erased. This cannot be undone.")
        }
    }
}
