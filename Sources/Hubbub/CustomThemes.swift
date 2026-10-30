import SwiftUI
import AppKit

/// Community theme packs: JSON files in ~/Library/Application Support/Hubbub/Themes reuse a built-in 3D set
/// (`base`) and override palette, wording, stations and character colours. See docs/THEMES.md.
struct ThemeParseError: Error { let message: String; init(_ m: String) { message = m } }

struct CustomTheme: Codable, Identifiable, Equatable {
    struct Palette: Codable, Equatable {
        var background, ambient, keyLight, fillLight, accent: String?
    }
    struct Characters: Codable, Equatable {
        var captainTitle, subagentRole: String?
        var captainShirt: String?
        var shirts, skins: [String]?
    }
    struct StationDef: Codable, Equatable {
        var kind: Int?
        var label, emoji: String?
    }
    struct Phrases: Codable, Equatable {
        var idle, working, success, failure: [String]?
    }
    struct Labels: Codable, Equatable {
        var boardTitle, roomNoun, quota, empty, idle, thinking: String?
    }
    struct AgeSign: Codable, Equatable {
        var title, subtitle: String?
    }

    var id: String
    var title: String
    var emoji: String
    var base: String
    var blurb: String?
    var palette: Palette?
    var characters: Characters?
    var stations: [StationDef]?
    var phrases: Phrases?
    var labels: Labels?
    var ageSign: AgeSign?

    var baseTheme: Theme { Theme(rawValue: base) ?? .space }
    var raw: String { "custom:\(id)" }
    /// Changes whenever the file content changes, so the stage rebuilds after a reload.
    var fingerprint: String { "\(id)#\((try? JSONEncoder().encode(self))?.hashValue ?? 0)" }

    static let baseNames = ["space", "kitchen", "prison", "football", "farm"]

    static func hex(_ s: String?) -> UInt32? {
        guard var t = s?.trimmingCharacters(in: .whitespaces) else { return nil }
        if t.hasPrefix("#") { t.removeFirst() } else if t.hasPrefix("0x") { t.removeFirst(2) }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return v
    }
    func color(_ s: String?) -> UInt32? { Self.hex(s) }
    func colors(_ a: [String]?) -> [UInt32] { (a ?? []).compactMap(Self.hex) }

    /// Returns a human-readable problem, or nil when the pack is usable.
    func validate() -> String? {
        if id.isEmpty || id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) == nil { return "id must be letters, digits, '-' or '_'" }
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return "title is empty" }
        if emoji.trimmingCharacters(in: .whitespaces).isEmpty { return "emoji is empty" }
        if !Self.baseNames.contains(base) { return "base '\(base)' must be one of \(Self.baseNames.joined(separator: ", "))" }
        let p = palette
        for (n, v) in [("background", p?.background), ("ambient", p?.ambient), ("keyLight", p?.keyLight), ("fillLight", p?.fillLight),
                       ("accent", p?.accent), ("captainShirt", characters?.captainShirt)] where v != nil && Self.hex(v) == nil {
            return "\(n) '\(v!)' is not a #rrggbb colour"
        }
        for v in (characters?.shirts ?? []) + (characters?.skins ?? []) where Self.hex(v) == nil { return "'\(v)' is not a #rrggbb colour" }
        if let s = stations {
            if s.count > 4 { return "stations has \(s.count) entries (max 4)" }
            if s.contains(where: { ($0.kind ?? 0) < 0 || ($0.kind ?? 0) > 3 }) { return "station kind must be 0-3" }
        }
        return nil
    }

    static func parse(_ data: Data) -> Result<CustomTheme, ThemeParseError> {
        do {
            let t = try JSONDecoder().decode(CustomTheme.self, from: data)
            if let problem = t.validate() { return .failure(ThemeParseError(problem)) }
            return .success(t)
        } catch let DecodingError.keyNotFound(k, _) {
            return .failure(ThemeParseError("missing required field '\(k.stringValue)'"))
        } catch let DecodingError.typeMismatch(_, c), let DecodingError.valueNotFound(_, c) {
            return .failure(ThemeParseError("wrong type at \(c.codingPath.map(\.stringValue).joined(separator: "."))"))
        } catch DecodingError.dataCorrupted {
            return .failure(ThemeParseError("not valid JSON"))
        } catch {
            return .failure(ThemeParseError(error.localizedDescription))
        }
    }

    func expand(_ template: String, age: Double, days: Int) -> String {
        template.replacingOccurrences(of: "{days}", with: "\(days)")
            .replacingOccurrences(of: "{age}", with: MetricsFmt.age(age))
            .replacingOccurrences(of: "{minutes}", with: "\(Int(age / 60))")
    }
}

@MainActor
final class CustomThemes: ObservableObject {
    static let shared = CustomThemes()
    /// Theme currently shown by the stage; read synchronously by `Theme` wording/station accessors.
    nonisolated(unsafe) static var active: CustomTheme?

    private init() { reload() }

    @Published private(set) var themes: [CustomTheme] = []
    @Published private(set) var errors: [String] = []

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hubbub/Themes", isDirectory: true)
    }

    /// `custom:<id>` selects a pack; anything else is a built-in raw value.
    static func customID(_ raw: String) -> String? { raw.hasPrefix("custom:") ? String(raw.dropFirst(7)) : nil }

    func theme(_ id: String) -> CustomTheme? { themes.first { $0.id == id } }

    func resolve(_ raw: String) -> (Theme, CustomTheme?) {
        if let id = Self.customID(raw), let c = theme(id) { return (c.baseTheme, c) }
        return (Theme.resolve(raw), nil)
    }

    func reload() {
        let r = Self.load(from: Self.folder, seedingIfEmpty: true)
        if r.themes != themes { themes = r.themes }
        if r.errors != errors { errors = r.errors }
        if let a = Self.active { Self.active = r.themes.first { $0.id == a.id } }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    nonisolated static func load(from dir: URL, seedingIfEmpty: Bool) -> (themes: [CustomTheme], errors: [String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "json" }
        // The example is seeded once, so deleting every theme file keeps the folder empty.
        let seeded = UserDefaults.standard.bool(forKey: "themesSeeded")
        if !files.isEmpty && seedingIfEmpty && !seeded { UserDefaults.standard.set(true, forKey: "themesSeeded") }
        if files.isEmpty && seedingIfEmpty && !seeded {
            UserDefaults.standard.set(true, forKey: "themesSeeded")
            let f = dir.appendingPathComponent("example-cyberpunk.json")
            try? exampleJSON.write(to: f, atomically: true, encoding: .utf8)
            files = [f]
        }
        var out: [CustomTheme] = [], errs: [String] = []
        var seen = Set<String>()
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: f) else { errs.append("\(f.lastPathComponent): cannot read file"); continue }
            switch CustomTheme.parse(data) {
            case .success(let t):
                if seen.insert(t.id).inserted { out.append(t) } else { errs.append("\(f.lastPathComponent): duplicate id '\(t.id)'") }
            case .failure(let m): errs.append("\(f.lastPathComponent): \(m.message)")
            }
        }
        return (out, errs)
    }

    nonisolated static let exampleJSON = #"""
    {
      "id": "cyberpunk",
      "title": "Neon Station",
      "emoji": "🌃",
      "base": "space",
      "blurb": "A neon-soaked orbital hub. The fixer runs the crew of runners.",
      "palette": {
        "background": "#07020f",
        "ambient": "#8a6bd8",
        "keyLight": "#ffd0f2",
        "fillLight": "#00e5ff",
        "accent": "#ff2bd6"
      },
      "characters": {
        "captainTitle": "Fixer",
        "subagentRole": "runner",
        "captainShirt": "#2b0f4a",
        "shirts": ["#1c1c3a", "#3a1240", "#0f3a4a", "#4a1030"],
        "skins": ["#f2c9a0", "#c68642", "#8d5524", "#ffdbb4"]
      },
      "stations": [
        { "kind": 0, "label": "Net scan", "emoji": "🛰️" },
        { "kind": 1, "label": "Chrome workshop", "emoji": "🦾" },
        { "kind": 2, "label": "Overclock bay", "emoji": "⚡️" },
        { "kind": 3, "label": "Black market", "emoji": "💾" }
      ],
      "phrases": {
        "idle": ["Need some synth-coffee…", "Neon flickers…"],
        "working": ["Jacking in", "Rerouting the grid", "Patching the firewall"],
        "success": ["Gig complete! 💰", "Ice broken! 🧊"],
        "failure": ["Flatlined! 🚨", "Trace detected! 💥"]
      },
      "labels": {
        "boardTitle": "THE CREW",
        "roomNoun": "Hideout",
        "quota": "Credits",
        "empty": "The grid is quiet…",
        "idle": "💭 Waiting for a gig",
        "thinking": "🧠 Hacking the mainframe…"
      },
      "ageSign": { "title": "🌃 Night {days}", "subtitle": "online {age}" }
    }
    """#
}

/// Override accessors used by `Theme` and the scene code; each returns nil unless the active pack is based on `theme`.
extension Theme {
    var ov: CustomTheme? { CustomThemes.active.flatMap { $0.baseTheme == self ? $0 : nil } }
}
