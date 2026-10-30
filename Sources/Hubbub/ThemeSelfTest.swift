import Foundation

/// `Hubbub --selftest-themes`: parses the bundled example, a broken file and a missing-base file in a scratch folder.
enum ThemeSelfTest {
    @MainActor static func run() -> Bool {
        var ok = true
        func check(_ name: String, _ cond: Bool) { print(cond ? "PASS" : "FAIL", name); if !cond { ok = false } }

        guard case .success(let ex) = CustomTheme.parse(Data(CustomThemes.exampleJSON.utf8)) else {
            print("FAIL example parses"); return false
        }
        check("example parses", ex.id == "cyberpunk" && ex.baseTheme == .space)
        check("example has 4 stations", ex.stations?.count == 4)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hubbub-theme-selftest-\(getpid())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ n: String, _ s: String) { try? s.write(to: dir.appendingPathComponent(n), atomically: true, encoding: .utf8) }
        write("good.json", CustomThemes.exampleJSON)
        write("broken.json", "{ \"id\": \"x\", ")
        write("nobase.json", #"{ "id": "nb", "title": "No base", "emoji": "❓" }"#)
        write("badbase.json", #"{ "id": "bb", "title": "Bad", "emoji": "❓", "base": "moon" }"#)
        write("badcolor.json", #"{ "id": "bc", "title": "Bad", "emoji": "❓", "base": "farm", "palette": { "accent": "red" } }"#)
        let r = CustomThemes.load(from: dir, seedingIfEmpty: false)
        r.errors.forEach { print("  error:", $0) }
        check("only the valid file loads", r.themes.map(\.id) == ["cyberpunk"])
        check("4 invalid files reported", r.errors.count == 4)
        check("missing base reported", r.errors.contains { $0.hasPrefix("nobase.json") && $0.contains("base") })

        CustomThemes.active = ex
        check("station override", Theme.space.stations[1].label == "Chrome workshop" && Theme.kitchen.stations[1].label != "Chrome workshop")
        check("captain title", Theme.space.captainRole == "Fixer")
        CustomThemes.active = nil
        check("built-in untouched", Theme.space.captainRole == "Commander")
        check("label contrast", LabelContrastTest.run())
        let fresh = ["impostor", "wizard", "galactic", "fellowship"]
        check("new themes registered", fresh.allSatisfy { Theme(rawValue: $0) != nil })
        for th in Theme.allCases {
            let texts = [th.title, th.icon, th.blurb, th.captainRole, th.subRole, th.quotaLabel, th.roomNoun, th.emptyText, th.idleText,
                         th.thinkingText, th.celebrateLine, th.panicLine, th.tiredLine] + th.stations.map(\.label) + (0..<4).flatMap { th.chatter(kind: $0) }
            check("theme data \(th.rawValue)", th.stations.count == 4 && !th.previewColors.isEmpty && texts.allSatisfy { !$0.isEmpty }
                  && (0..<4).allSatisfy { th.action(for: ["bash", "edit", "view", "task"][$0]) != nil })
            _ = Environments.build(th)
            _ = Rig.outfit(th, captain: false, v: 1)
            _ = Stage.motion(th, 1)
        }
        return ok
    }
}
