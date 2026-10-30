import Foundation
import AppKit

/// Headless checks for navigation, routing and sizing logic used outside Settings (`--selftest-ui`).
enum UISelfTest {
    @MainActor static func run() -> Bool {
        var ok = true
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL \(m)"); ok = false } }

        check(Theme.named("space") == .space && Theme.named("Space") == .space, "theme by raw value")
        check(Theme.named("sneaky-ship") != nil && Theme.named("Sneaky Ship") == Theme.named("sneaky_ship"), "theme by title ignores punctuation")
        check(Theme.named("Hillside Quest") == .fellowship && Theme.named("spell academy") == .wizard && Theme.named("Galactic Fleet") == .galactic, "theme titles resolve")
        check(Theme.named("") == nil && Theme.named("---") == nil && Theme.named("nope") == nil, "unknown theme names rejected")
        for t in Theme.allCases { check(Theme.named(t.rawValue) == t && Theme.named(t.title) == t, "theme \(t.rawValue) addressable by raw value and title") }

        let tabs: [Screen] = [.live, .history, .insights, .achievements]
        check(tabs.allSatisfy(\.isTab) && !Screen.settings.isTab && !Screen.detail("x").isTab, "tab screens")

        var mode = CameraMode.free
        var seen: [CameraMode] = []
        for _ in CameraMode.allCases { seen.append(mode); mode = mode.next }
        check(mode == .free && Set(seen).count == CameraMode.allCases.count, "camera mode cycles through all modes")

        for size in PopoverSize.allCases {
            let small = size.contentSize(on: nil)
            check(small.width > 0 && small.height > 0, "popover size \(size.rawValue) positive")
        }
        check(PopoverSize.comfortable.width > PopoverSize.compact.width && PopoverSize.comfortable.height > PopoverSize.compact.height, "comfortable is larger")

        check(ArenaMath.clampZoom(.nan) == 1 && ArenaMath.clampZoom(1e9) == ArenaMath.zoomRange.upperBound && ArenaMath.clampZoom(-5) == ArenaMath.zoomRange.lowerBound, "zoom clamps")
        var z: CGFloat = 1
        for _ in 0..<100 { z = ArenaMath.steppedZoom(z, direction: 1) }
        check(z == ArenaMath.zoomRange.upperBound, "zoom-in steps stop at the maximum")
        for _ in 0..<100 { z = ArenaMath.steppedZoom(z, direction: -1) }
        check(z == ArenaMath.zoomRange.lowerBound, "zoom-out steps stop at the minimum")

        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func rec(_ id: String, _ d: Date) -> SessionRecord {
            SessionRecord(SessionInfo(id: id, name: id, cwd: "/x", model: "m", lastEvent: d, state: .idle, currentTool: nil, subagents: [],
                                      inputTokens: 1, outputTokens: 1, toolCalls: 0, failures: 0, provider: "copilot"))
        }
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let groups = SessionBrowser.dayGroups([rec("a", day), rec("b", day.addingTimeInterval(-3600)), rec("c", day.addingTimeInterval(-86400))], calendar: cal)
        check(groups.count == 2 && groups[0].items.map(\.id) == ["a", "b"] && groups[1].items.map(\.id) == ["c"], "history day groups")

        check(Tip.allCases.allSatisfy { !$0.text.isEmpty && !$0.icon.isEmpty }, "tips have text and icon")
        check(Set(HotkeyPreset.allCases.map { "\($0.keyCode)-\($0.modifiers)" }).count == HotkeyPreset.allCases.count, "hotkey presets are distinct")

        let router = AppRouter.shared
        var opened = 0
        router.openPopoverHandler = { opened += 1 }
        router.open(screen: "history"); router.open(sessionID: "s1")
        check(opened == 2 && router.pendingScreen == "history" && router.pendingSessionID == "s1", "router stores pending request and opens the popover")
        router.pendingScreen = nil; router.pendingSessionID = nil; router.openPopoverHandler = nil

        print(ok ? "ui selftest OK" : "ui selftest FAILED")
        return ok
    }
}
