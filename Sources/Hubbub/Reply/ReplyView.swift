import SwiftUI

/// Shown in the session panel: the question the agent is blocked on, with reply controls when a channel is enabled.
struct ReplySection: View {
    let session: SessionInfo
    @ObservedObject private var center = ReplyCenter.shared
    @State private var text = ""
    @State private var note: String?

    var body: some View {
        let q = center.question(for: session)
        let st = center.status[session.id]
        if q != nil || st != nil || session.waitingApproval {
            VStack(alignment: .leading, spacing: 8) {
                if let q { questionCard(q) }
                else if st == nil { fallbackBanner }
                if let st { statusLine(st) }
            }
        }
    }

    private var fallbackBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Waiting for your approval or answer").font(.caption.bold()).lineLimit(1)
            Spacer(minLength: 4)
            Button("Open in Terminal") { SessionActions.openTerminal(session) { note = $0 } }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.6), lineWidth: 1))
    }

    private func questionCard(_ q: PendingQuestion) -> some View {
        let avail = center.availability(session: session, question: q)
        let canAct: Bool = { if case .off = avail { return false } else { return true } }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: q.isPermission ? "hand.raised.fill" : "questionmark.bubble.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(q.title).font(.caption.bold()).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let d = q.detail {
                        Text(d).font(.system(size: 10, design: .monospaced)).lineLimit(6).textSelection(.enabled)
                            .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.15)))
                    }
                }
            }
            if q.isPermission {
                HStack(spacing: 6) {
                    Button("Approve") { center.reply(.approve, session: session, question: q) }
                        .buttonStyle(.borderedProminent).tint(.green).disabled(!canAct)
                    Button("Deny") { center.reply(.deny, session: session, question: q) }
                        .buttonStyle(.bordered).tint(.red).disabled(!canAct)
                    if q.source == .hook {
                        Button("Ask in terminal") { center.askInTerminal(session: session, question: q) }.buttonStyle(.bordered)
                    } else {
                        Button("Open in Terminal") { SessionActions.openTerminal(session) { note = $0 } }.buttonStyle(.bordered)
                    }
                }.controlSize(.small)
            } else {
                if !q.unsupportedFields.isEmpty {
                    Text("This form has more than one question (\(q.unsupportedFields.prefix(4).joined(separator: ", "))). Answer it in your terminal.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(q.options.prefix(8)) { o in
                    Button { center.reply(.choice(o.index), session: session, question: q) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.label).font(.caption).multilineTextAlignment(.leading)
                            if let d = o.detail { Text(d).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(!canAct || !q.canAnswerInApp)
                }
                if q.options.count > 8 { Text("+\(q.options.count - 8) more — answer in your terminal").font(.caption2).foregroundStyle(.secondary) }
                if (q.allowsFreeText || q.kind == .freeText), q.canAnswerInApp {
                    HStack(spacing: 6) {
                        TextField("Type a reply", text: $text).textFieldStyle(.roundedBorder).font(.caption)
                            .onSubmit { send(q) }.disabled(!canAct)
                        Button("Send") { send(q) }.buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(!canAct || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                HStack { Button("Open in Terminal") { SessionActions.openTerminal(session) { note = $0 } }.buttonStyle(.bordered).controlSize(.small) }
            }
            footer(avail)
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func send(_ q: PendingQuestion) {
        let t = text
        text = ""
        center.reply(.text(t), session: session, question: q)
    }

    @ViewBuilder private func footer(_ a: ReplyAvailability) -> some View {
        switch a {
        case .hook: Text("Answered through your opt-in permission hook. Nothing is sent unless you press a button.").font(.caption2).foregroundStyle(.secondary)
        case .terminal: Text("Your reply is typed into this session's terminal when you press a button (opt-in).").font(.caption2).foregroundStyle(.secondary)
        case .off(let why): Text("\(why). Enable replying in Settings → Alerts, or answer in your terminal.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func statusLine(_ st: ReplyStatus) -> some View {
        let color: Color = { switch st { case .failed, .unconfirmed: .red; case .confirmed: .green; default: .secondary } }()
        return HStack(spacing: 6) {
            Text(st.text).font(.caption2).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if case .sending = st {} else { Button("Dismiss") { center.dismissStatus(session.id) }.buttonStyle(.plain).font(.caption2) }
        }
    }
}
