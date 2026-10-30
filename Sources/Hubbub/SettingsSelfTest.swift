import SwiftUI
import AppKit

/// `--selftest-settings`: flips the persisted settings and asserts the observable effect on the model that reads them.
/// Touched keys are restored afterwards.
@MainActor
enum SettingsSelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL settings: \(m)"); ok = false } }
        let d = UserDefaults.standard
        var saved: [String: Any?] = [:]
        func set(_ key: String, _ v: Any?) {
            if saved[key] == nil { saved[key] = d.object(forKey: key) }
            if let v { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
        }
        defer { for (k, v) in saved { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }

        // Notifications: master gates every kind; failed defaults off, the others on.
        set(NotifyKey.master, nil); for k in [NotifyKey.approval, NotifyKey.stuck, NotifyKey.failed, NotifyKey.finished] { set(k, nil) }
        check(NotifyKey.isOn(NotifyKey.approval) && NotifyKey.isOn(NotifyKey.stuck) && NotifyKey.isOn(NotifyKey.finished), "default kinds on")
        check(!NotifyKey.isOn(NotifyKey.failed), "failed defaults off")
        set(NotifyKey.failed, true); check(NotifyKey.isOn(NotifyKey.failed), "failed toggle on")
        set(NotifyKey.stuck, false); check(!NotifyKey.isOn(NotifyKey.stuck) && NotifyKey.isOn(NotifyKey.approval), "per-kind toggle independent")
        set(NotifyKey.master, false); check(!NotifyKey.isOn(NotifyKey.approval) && !NotifyKey.isOn(NotifyKey.failed), "master off gates all")

        // Appearance readers
        set("ambienceLevel", "full"); set("ambienceTime", "night"); set(A11y.motionKey, "off")
        check(AmbienceLevel.current == .full && AmbienceTime.current == .night, "ambience level/time")
        set("ambienceLevel", "bogus"); check(AmbienceLevel.current == .subtle, "invalid ambience falls back")
        set(A11y.motionKey, "on"); check(AmbienceLevel.current == .off, "reduce motion forces ambience off")
        set(A11y.motionKey, "off")
        for m in CameraMode.allCases { set(CameraMode.storageKey, m.rawValue); check(CameraMode.current == m, "camera \(m)") }
        set(CameraMode.storageKey, "bogus"); check(CameraMode.current == .free, "invalid camera falls back")
        set(PopoverSize.key, "comfortable"); check(PopoverSize.current == .comfortable && PopoverSize.current.width > PopoverSize.compact.width, "popover size")
        set(PopoverSize.key, nil); check(PopoverSize.current == .compact, "popover size default")
        set(Halloween.key, "off"); check(!Halloween.isActive(mode: Halloween.storedMode, env: [:]), "halloween off")
        set(Halloween.key, "on"); check(Halloween.isActive(mode: Halloween.storedMode, env: [:]), "halloween on")
        set("showMascot", false); check(!SceneFX.mascotEnabled, "mascot off")
        set("showMascot", nil); check(SceneFX.mascotEnabled, "mascot default on")
        set("team", Team.allCases.last!.rawValue); check(Team.current == Team.allCases.last!, "team")
        set(A11y.transparencyKey, "on"); check(A11y.reduceTransparency, "transparency override on")
        set(A11y.transparencyKey, "off"); check(!A11y.reduceTransparency, "transparency override off")
        set(A11y.contrastKey, "on"); check(A11y.increaseContrast, "contrast override on")
        set(A11y.contrastKey, "off"); check(!A11y.increaseContrast, "contrast override off")

        // Menu bar display
        let monitor = SessionMonitor(), quota = QuotaService()
        quota.quota = Quota(entitlement: 100, remaining: 60, percentRemaining: 60, used: 40, resetDate: "", plan: "pro", unlimited: false)
        set("menuBarDisplay", MenuBarDisplay.iconAndPercent.rawValue)
        check(MenuBarStatus.make(monitor: monitor, quota: quota, budget: BudgetCenter.shared).text == "40%", "menu bar shows percent")
        set("menuBarDisplay", MenuBarDisplay.iconOnly.rawValue)
        check(MenuBarStatus.make(monitor: monitor, quota: quota, budget: BudgetCenter.shared).text == nil, "menu bar icon only")

        // Sound, music, fun, HUD
        set(SoundCenter.enabledKey, true); set(SoundCenter.volumeKey, 0.2)
        check(SoundCenter.shared.enabled && abs(SoundCenter.shared.volume - 0.2) < 0.001, "sfx enabled/volume")
        set(MusicCenter.enabledKey, true); set(MusicCenter.volumeKey, 0.8)
        check(MusicCenter.shared.enabled && abs(MusicCenter.shared.volume - 0.8) < 0.001, "music enabled/volume")
        check(MusicCenter.shouldPlay(enabled: true, visible: true, lowPower: false) && !MusicCenter.shouldPlay(enabled: true, visible: false, lowPower: false), "music gating")
        set(RaceOverlay.enabledKey, true); check(RaceOverlay.enabled, "race mode")
        set(GuestLayer.enabledKey, true); check(GuestLayer.enabled, "guests on")
        set(GuestLayer.enabledKey, false); check(!GuestLayer.enabled, "guests off")
        set(HudController.enabledKey, true); set(HudController.clickThroughKey, true)
        check(HudController.shared.isEnabled && HudController.shared.clickThrough, "hud keys")

        // Providers
        let reg = ProviderRegistry.shared
        set("provider.enabled.claude", nil)
        let auto = reg.isEnabled("claude")
        check(auto == (reg.provider("claude")?.isAvailable ?? false), "provider auto = detected")
        set("provider.enabled.claude", false); check(!reg.isEnabled("claude") && !reg.enabled.contains { $0.id == "claude" }, "provider off")
        set("provider.enabled.claude", true); check(reg.isEnabled("claude") && reg.enabled.contains { $0.id == "claude" }, "provider on")
        set("providerQuota.enabled.claude", true)
        check(ProviderQuotaService.shared.active.contains("claude"), "quota opt-in active when provider on")
        set("provider.enabled.claude", false)
        check(!ProviderQuotaService.shared.active.contains("claude"), "quota opt-in inactive when provider off")

        // Budget: limits, unit and the exceeded flag follow the settings without a session update from the monitor
        set(BudgetCenter.unitKey, "tokens"); set(BudgetCenter.dailyKey, 1.0); set(BudgetCenter.sessionKey, 0.0); set(BudgetCenter.pauseKey, true)
        set("budgetFired", nil)
        var s = SessionInfo(id: "b", name: "Build", cwd: "/x", model: "m", lastEvent: Date(), state: .working, currentTool: nil,
                            subagents: [], inputTokens: 5000, outputTokens: 0, toolCalls: 1)
        s.costCredits = 3
        let b = BudgetCenter.shared
        check(b.tokenMode && b.dailyLimit == 1, "budget keys read")
        b.update([s]); check(b.exceeded && b.showWarning, "token budget exceeded")
        set(BudgetCenter.pauseKey, false); check(!b.showWarning, "warning toggle")
        set(BudgetCenter.dailyKey, 0.0); b.update([s]); check(!b.exceeded, "limit cleared resets exceeded")
        set(BudgetCenter.unitKey, "credits"); set(BudgetCenter.dailyKey, 2.0); b.update([s]); check(b.exceeded && !b.tokenMode, "credit budget exceeded")
        set(BudgetCenter.dailyKey, 0.0); b.update([s])

        // Quiet hours hold notifications and release them when switched off
        let g = FocusGuard.shared
        let now = QuietHours.minuteOfDay(Date())
        set(FocusGuard.Key.respectFocus, false)
        set(FocusGuard.Key.quietEnabled, true)
        set(FocusGuard.Key.quietStart, (now + 1440 - 5) % 1440); set(FocusGuard.Key.quietEnd, (now + 60) % 1440)
        check(g.quietNow && g.isSuppressing, "quiet hours active")
        check(g.intercept(.init(title: "t", body: "b", sessionID: nil, id: "x")) && g.heldCount == 1, "notification held")
        set(FocusGuard.Key.quietEnabled, false); g.evaluate()
        check(!g.isSuppressing && g.heldCount == 0, "quiet hours off releases held")
        set(FocusGuard.Key.quietStart, now); set(FocusGuard.Key.quietEnd, now)
        set(FocusGuard.Key.quietEnabled, true); check(!g.quietNow, "empty quiet range holds nothing")
        set(FocusGuard.Key.quietEnabled, false); g.evaluate()

        // Sync, reply, hotkey, update, progression
        set(TeamSync.titlesKey, true); set(TeamSync.tokensKey, false); set(TeamSync.activeKey, true)
        let o = TeamSync.shared.options
        check(o.shareTitles && !o.shareTokens && o.onlyActive, "sync options")
        set(TeamSync.nameKey, "  "); check(TeamSync.shared.machineName == TeamSync.defaultName, "blank machine name falls back")
        set(TeamSync.folderKey, ""); check(TeamSync.shared.folder == nil, "no folder = nil")
        set(ReplyKey.hook, true); set(ReplyKey.terminal, true)
        check(ReplyCenter.shared.hookEnabled && ReplyCenter.shared.terminalEnabled, "reply keys")
        set("hotkeyEnabled", nil); set("hotkeyPreset", nil)
        let hk = HotkeyManager.shared
        let (e0, p0) = (hk.enabled, hk.presetRaw)
        hk.enabled = false; hk.presetRaw = HotkeyPreset.optSpace.rawValue
        check(d.object(forKey: "hotkeyEnabled") as? Bool == false && d.string(forKey: "hotkeyPreset") == "optSpace", "hotkey persisted")
        check(Set(HotkeyPreset.allCases.map { "\($0.keyCode)/\($0.modifiers)" }).count == HotkeyPreset.allCases.count, "hotkey presets distinct")
        hk.enabled = e0; hk.presetRaw = p0
        set(Progression.enabledKey, false); check(!Progression.enabled && Progression.unlockedCosmetics(level: 99, enabled: Progression.enabled).isEmpty, "progression off")
        set("updateCheckAuto", false); check(UserDefaults.standard.object(forKey: "updateCheckAuto") as? Bool == false, "update auto persisted")

        // Reduce transparency swaps materials for an opaque fill
        set(A11y.transparencyKey, "on"); let solid = "\(A11y.panelFill())"
        set(A11y.transparencyKey, "off"); check("\(A11y.panelFill())" != solid, "panel fill follows reduce transparency")

        // Community theme example is seeded only once
        let dir = FileManager.default.currentDirectoryPath + "/.selftest-settings"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        set("themesSeeded", nil)
        let url = URL(fileURLWithPath: dir)
        check(CustomThemes.load(from: url, seedingIfEmpty: true).themes.count == 1, "example theme seeded on first run")
        try? FileManager.default.removeItem(at: url.appendingPathComponent("example-cyberpunk.json"))
        check(CustomThemes.load(from: url, seedingIfEmpty: true).themes.isEmpty, "deleted themes stay deleted")

        print(ok ? "settings selftest OK" : "settings selftest FAILED")
        return ok
    }
}

/// `--snapshot-settings general|appearance|providers|alerts|advanced out.png [width]`: renders one Settings tab offscreen.
enum SettingsSnapshot {
    @MainActor static func run(_ args: [String]) {
        guard args.count >= 2, let tab = SettingsTab(rawValue: args[0]) else {
            print("usage: --snapshot-settings general|appearance|providers|alerts|advanced out.png [width]"); return
        }
        let width = args.count > 2 ? Double(args[2]) ?? 440 : 440
        UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
        let monitor = SessionMonitor()
        let root = SettingsView(monitor: monitor, stage: Stage()).frame(width: width - 24, height: 1500).padding(12)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1524), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[1]))
        }
        print("settings \(tab.rawValue) @\(Int(width))pt")
    }
}
