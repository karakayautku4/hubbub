import SwiftUI
import AppKit

/// Per-preference override of the system accessibility setting.
enum A11yOverride: String, CaseIterable, Identifiable {
    case system, on, off
    var id: String { rawValue }
}

/// Resolves accessibility preferences: the Settings override wins, otherwise the macOS setting applies.
enum A11y {
    static let motionKey = "a11yReduceMotion"
    static let contrastKey = "a11yIncreaseContrast"
    static let transparencyKey = "a11yReduceTransparency"

    private static func resolve(_ key: String, system: Bool) -> Bool {
        switch A11yOverride(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system {
        case .system: system
        case .on: true
        case .off: false
        }
    }

    static var reduceMotion: Bool { resolve(motionKey, system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    static var increaseContrast: Bool { resolve(contrastKey, system: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast) }
    static var reduceTransparency: Bool { resolve(transparencyKey, system: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) }
}

extension A11y {
    /// Translucent material, or an opaque window colour while Reduce transparency is on.
    static func panelFill(_ material: Material = .regularMaterial) -> AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(material)
    }
}

/// Text descriptions of the 3D stage for VoiceOver (the SceneKit view itself exposes nothing).
enum A11yNarration {
    /// Short state word for a session; shape-based in the UI, spelled out here.
    static func status(_ s: SessionInfo, attention: AttentionLevel) -> String {
        if attention == .stuck { return "stuck" }
        if attention == .failed { return "failed" }
        if s.waitingApproval { return "waiting for approval" }
        switch s.state {
        case .working: return s.currentTool.map { "working, using \($0)" } ?? "working"
        case .idle: return "idle"
        case .offline: return "offline"
        }
    }

    static func summary(themeTitle: String, sessions: [SessionInfo], attention: [String: AttentionLevel]) -> String {
        if sessions.isEmpty { return "\(themeTitle) scene, no sessions" }
        let needs = sessions.filter { (attention[$0.id] ?? .none) != .none || $0.waitingApproval }
        let working = sessions.filter { $0.state == .working }.count
        var s = "\(themeTitle) scene, \(sessions.count) session\(sessions.count == 1 ? "" : "s"), \(working) working"
        if !needs.isEmpty { s += ", \(needs.count) need\(needs.count == 1 ? "s" : "") attention" }
        let detail = sessions.prefix(5).map { x -> String in
            let n = x.subagents.count
            return "\(x.name): \(status(x, attention: attention[x.id] ?? .none))" + (n > 0 ? ", \(n) sub-agent\(n == 1 ? "" : "s")" : "")
        }
        s += ". " + detail.joined(separator: "; ")
        if sessions.count > 5 { s += "; and \(sessions.count - 5) more" }
        return s
    }

    /// One token per session; a change in any status triggers a VoiceOver announcement.
    static func announcements(old: [String: String], new: [String: String], names: [String: String]) -> [String] {
        new.compactMap { id, st in
            guard let before = old[id], before != st else { return nil }
            return "\(names[id] ?? "Session"): \(st)"
        }.sorted()
    }

    /// Posts a polite live-region style announcement.
    @MainActor static func announce(_ text: String) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

/// Adds a visible outline when Increase Contrast is on, so translucent chips and cards keep a clear edge.
struct A11yContrastBorder<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var envContrast
    func body(content: Content) -> some View {
        let on = envContrast == .increased || A11y.increaseContrast
        content.overlay(shape.strokeBorder(Color.primary.opacity(on ? 0.7 : 0), lineWidth: on ? 1 : 0))
    }
}

extension View {
    func a11yContrastBorder<S: InsettableShape>(_ shape: S) -> some View { modifier(A11yContrastBorder(shape: shape)) }
}

/// Settings > Appearance card with overrides for the system accessibility preferences.
struct AccessibilitySettingsCard: View {
    @AppStorage(A11y.motionKey) private var motion = A11yOverride.system.rawValue
    @AppStorage(A11y.contrastKey) private var contrast = A11yOverride.system.rawValue
    @AppStorage(A11y.transparencyKey) private var transparency = A11yOverride.system.rawValue

    var body: some View {
        SettingsCard(title: "Accessibility",
                     footer: "\"System\" follows macOS. Reduce motion stops weather, camera moves and confetti. Status is always shown with an icon as well as a colour.") {
            row("Reduce motion", $motion)
            row("Increase contrast", $contrast)
            row("Reduce transparency", $transparency)
        }
    }

    private func row(_ title: String, _ binding: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: binding) {
                Text("System").tag(A11yOverride.system.rawValue)
                Text("On").tag(A11yOverride.on.rawValue)
                Text("Off").tag(A11yOverride.off.rawValue)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 190)
        }
        .accessibilityElement(children: .contain)
    }
}

enum A11ySelfTest {
    @MainActor static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL a11y: \(m)"); ok = false } }
        let d = UserDefaults.standard
        let saved = d.string(forKey: A11y.motionKey)
        d.set("on", forKey: A11y.motionKey); check(A11y.reduceMotion, "override on")
        d.set("off", forKey: A11y.motionKey); check(!A11y.reduceMotion, "override off")
        if let saved { d.set(saved, forKey: A11y.motionKey) } else { d.removeObject(forKey: A11y.motionKey) }

        var s = SessionInfo(id: "a", name: "Build", cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: "bash",
                            subagents: [], inputTokens: 0, outputTokens: 0, toolCalls: 0)
        check(A11yNarration.status(s, attention: .failed) == "failed", "failed status")
        check(A11yNarration.status(s, attention: .none) == "working, using bash", "working status")
        s.waitingApproval = true
        check(A11yNarration.status(s, attention: .none) == "waiting for approval", "approval status")
        let text = A11yNarration.summary(themeTitle: "Prison", sessions: [s], attention: ["a": .failed])
        check(text.contains("1 session,") && text.contains("1 needs attention") && text.contains("Build: failed"), "summary: \(text)")
        check(A11yNarration.summary(themeTitle: "Prison", sessions: [], attention: [:]).contains("no sessions"), "empty summary")
        let ann = A11yNarration.announcements(old: ["a": "idle", "b": "idle"], new: ["a": "failed", "b": "idle", "c": "idle"], names: ["a": "Build"])
        check(ann == ["Build: failed"], "announcements \(ann)")
        print(ok ? "a11y self-test OK" : "a11y self-test FAILED")
        return ok
    }
}
