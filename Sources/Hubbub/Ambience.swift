import SceneKit
import AppKit

/// User-facing ambience settings (persisted via @AppStorage keys "ambienceLevel" / "ambienceTime").
enum AmbienceLevel: String, CaseIterable, Identifiable {
    case off, subtle, full
    var id: String { rawValue }
    var title: String { switch self { case .off: "Off"; case .subtle: "Subtle"; case .full: "Full" } }
    var strength: Double { switch self { case .off: 0; case .subtle: 0.5; case .full: 1 } }
    static var current: AmbienceLevel {
        if A11y.reduceMotion { return .off }
        return AmbienceLevel(rawValue: Ambience.debugEnv["AMBIENCE_MODE"] ?? UserDefaults.standard.string(forKey: "ambienceLevel") ?? "") ?? .subtle
    }
}

enum AmbienceTime: String, CaseIterable, Identifiable {
    case auto, day, night
    var id: String { rawValue }
    var title: String { switch self { case .auto: "Auto"; case .day: "Day"; case .night: "Night" } }
    static var current: AmbienceTime { AmbienceTime(rawValue: UserDefaults.standard.string(forKey: "ambienceTime") ?? "") ?? .auto }
}

/// Day/night cycle from the local clock plus deterministic-by-day weather. Updates are throttled (every few seconds) and
/// weather lives inside the environment node, so it is dropped with the theme and costs nothing while the stage is not rendered.
@MainActor
final class Ambience {
    private struct Base {
        var bg: NSColor
        var ambColor: NSColor, ambI: CGFloat
        var keyColor: NSColor, keyI: CGFloat
        var fillColor: NSColor, fillI: CGFloat
    }

    /// Debug overrides (AMBIENCE_MODE / AMBIENCE_HOUR / AMBIENCE_WEATHER), read once: `ProcessInfo.environment` copies the whole environment on every access.
    nonisolated static let debugEnv: [String: String] = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("AMBIENCE_") }

    private var theme: Theme = .defaultTheme
    private weak var scene: SCNScene?
    private var lights: [SCNNode] = []
    private var base: Base?
    private var overlay: SCNNode?
    private var weatherNode: SCNNode?
    private var weatherKey = ""
    private var lastUpdate = -1000.0
    private var lastPoll = -1000.0
    private var lastSettings = ""
    private var disabled = false

    /// How much the real sky matters per theme: 0 = sealed (space, ship), 1 = fully outdoors.
    private static func outdoor(_ t: Theme) -> Double {
        if let o = ThemeExtensions.active?.outdoorLevel(t) { return o }
        return switch t {
        case .farm, .fellowship: 1
        case .football: 0.85
        case .prison: 0.6
        case .wizard: 0.35
        case .kitchen: 0.25
        default: 0
        }
    }

    func attach(scene: SCNScene, env: SCNNode, theme: Theme, lights: [SCNNode], custom: Bool) {
        self.scene = scene
        self.theme = theme
        self.lights = lights
        overlay = nil
        weatherNode = nil
        weatherKey = ""
        lastSettings = ""
        lastUpdate = -1000
        lastPoll = -1000
        disabled = custom || lights.count < 3
        scene.fogEndDistance = 0
        guard !disabled, let amb = lights[0].light, let sun = lights[1].light, let fill = lights[2].light else { disabled = true; return }
        base = Base(bg: (scene.background.contents as? NSColor) ?? .black,
                    ambColor: amb.color as? NSColor ?? .white, ambI: amb.intensity,
                    keyColor: sun.color as? NSColor ?? .white, keyI: sun.intensity,
                    fillColor: fill.color as? NSColor ?? .white, fillI: fill.intensity)
        // Night tint over the painted sky backdrop.
        let sky: (CGFloat, CGFloat, CGFloat, CGFloat)? = switch theme {
        case .farm, .prison: (120, 40, -11.9, 9)
        case .fellowship: (140, 44, -21.9, 10)
        default: nil
        }
        if let s = sky {
            let plane = SCNPlane(width: s.0, height: s.1)
            let m = SCNMaterial()
            m.diffuse.contents = NSColor(red: 0.03, green: 0.05, blue: 0.16, alpha: 1)
            m.lightingModel = .constant
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            plane.firstMaterial = m
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(0, s.3, s.2)
            n.opacity = 0
            n.castsShadow = false
            env.addChildNode(n)
            overlay = n
        }
    }

    /// Call every tick; does real work at most once per few seconds (or when settings change).
    func update(t: Double) {
        guard !disabled, let base, let scene else { return }
        // Settings are polled once a second; the day/night and weather work itself runs every few seconds.
        guard t - lastPoll >= 1 else { return }
        lastPoll = t
        let level = AmbienceLevel.current, time = AmbienceTime.current
        let settings = "\(level.rawValue)/\(time.rawValue)"
        guard settings != lastSettings || t - lastUpdate >= 5 else { return }
        lastSettings = settings
        lastUpdate = t

        let k = level.strength * Ambience.outdoor(theme)
        let date = Date()
        let hour = Ambience.hour(date)
        let day = Ambience.dayFactor(hour: hour, override: time)

        // Night factor in 0...1 scaled by theme/level strength; football's base look is already an evening match, so it brightens by day instead.
        let night = (1 - day) * k
        let brighten = theme == .football ? day * k : 0
        let dusk = Ambience.duskGlow(hour: hour, override: time) * k

        func mix(_ a: NSColor, _ b: NSColor, _ f: Double) -> NSColor {
            let x = a.usingColorSpace(.deviceRGB) ?? a, y = b.usingColorSpace(.deviceRGB) ?? b
            let f = CGFloat(max(0, min(1, f)))
            return NSColor(red: x.redComponent + (y.redComponent - x.redComponent) * f, green: x.greenComponent + (y.greenComponent - x.greenComponent) * f,
                           blue: x.blueComponent + (y.blueComponent - x.blueComponent) * f, alpha: 1)
        }
        let moon = Gfx.color(0x8fa6ff), nightSky = Gfx.color(0x070b20), warm = Gfx.color(0xffa35c), daySky = Gfx.color(0x8fc3ee)
        var bg = mix(base.bg, nightSky, night)
        bg = mix(bg, daySky, brighten)
        bg = mix(bg, Gfx.color(0xe58a5a), dusk * 0.35)
        scene.background.contents = bg

        if let amb = lights[0].light, let sun = lights[1].light, let fill = lights[2].light {
            amb.color = mix(mix(base.ambColor, moon, night), warm, dusk * 0.3)
            amb.intensity = base.ambI * CGFloat(1 - 0.65 * night + 0.25 * brighten)
            sun.color = mix(mix(base.keyColor, moon, night), warm, dusk * 0.6)
            sun.intensity = base.keyI * CGFloat(1 - 0.85 * night + 0.2 * brighten)
            // The accent light turns into a dimmer, warm lamp glow after dark.
            fill.color = mix(base.fillColor, warm, night * 0.6)
            fill.intensity = base.fillI * CGFloat(1 - 0.5 * night)
            scene.lightingEnvironment.intensity = 0.9 * CGFloat(1 - 0.85 * night + 0.15 * brighten)
        }
        overlay?.opacity = CGFloat(min(0.85, night * 0.85))

        applyWeather(level: level, night: 1 - day, date: date)
    }

    // MARK: Time of day

    static func hour(_ d: Date) -> Double {
        if let e = Ambience.debugEnv["AMBIENCE_HOUR"], let h = Double(e) { return h }
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
    }

    private static func smooth(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }

    /// 1 in full daylight, 0 at night; sunrise ≈ 6:30 and sunset ≈ 19:30 with 1.5 h smooth ramps.
    static func dayFactor(hour h: Double, override: AmbienceTime) -> Double {
        switch override {
        case .day: return 1
        case .night: return 0
        case .auto: return smooth((h - 5.75) / 1.5) * (1 - smooth((h - 18.75) / 1.5))
        }
    }

    /// Warm horizon glow peaking around sunrise/sunset.
    static func duskGlow(hour h: Double, override: AmbienceTime) -> Double {
        guard override == .auto else { return 0 }
        func bump(_ c: Double) -> Double { max(0, 1 - abs(h - c) / 1.25) }
        return max(bump(6.5), bump(19.5))
    }

    // MARK: Weather

    enum Kind: String { case none, rain, snow, fog, fireflies }

    /// Deterministic per local day + theme: a weather type that appears for a few hours of that day.
    static func forecast(day: Int, theme: Theme, hour h: Double) -> Kind {
        if let e = Ambience.debugEnv["AMBIENCE_WEATHER"] { return Kind(rawValue: e) ?? .none }
        let options: [Kind]
        switch theme {
        case .farm: options = [.rain, .fog, .fireflies, .none]
        case .fellowship: options = [.rain, .fog, .snow, .fireflies]
        case .football: options = [.rain, .snow, .none, .none]
        case .prison: options = [.rain, .fog, .none, .none]
        case .wizard: options = [.fireflies, .snow, .fog, .none]
        default: return .none
        }
        var x = UInt64(truncatingIfNeeded: day) &* 0x9E3779B97F4A7C15 ^ UInt64(theme.rawValue.hashValue & 0xffff) &* 0xBF58476D1CE4E5B9
        func next() -> UInt64 { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x }
        _ = next(); _ = next()
        let kind = options[Int(next() % UInt64(options.count))]
        let start = Double(next() % 16) + 4, len = Double(next() % 4) + 3
        return h >= start && h < start + len ? kind : .none
    }

    private func applyWeather(level: AmbienceLevel, night: Double, date: Date) {
        guard let scene else { return }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        var kind = level == .off ? Kind.none : Ambience.forecast(day: day, theme: theme, hour: Ambience.hour(date))
        // Fireflies only make sense after dusk.
        if kind == .fireflies && night < 0.5 && Ambience.debugEnv["AMBIENCE_WEATHER"] == nil { kind = .none }
        let key = "\(kind.rawValue)/\(level.rawValue)"
        guard key != weatherKey else { return }
        weatherKey = key
        weatherNode?.removeFromParentNode()
        weatherNode = nil
        scene.fogEndDistance = 0
        guard kind != .none, let env = scene.rootNode.childNode(withName: "env", recursively: false) else { return }
        let full = level == .full
        let node = SCNNode()
        node.name = "weather"
        switch kind {
        case .rain: node.addParticleSystem(Weather.rain(rate: full ? 160 : 70))
        case .snow: node.addParticleSystem(Weather.snow(rate: full ? 60 : 28))
        case .fireflies: node.addParticleSystem(Weather.fireflies(rate: full ? 7 : 4))
        case .fog:
            scene.fogColor = scene.background.contents as Any
            scene.fogStartDistance = full ? 24 : 34
            scene.fogEndDistance = full ? 62 : 90
            scene.fogDensityExponent = 1
        case .none: break
        }
        node.position = SCNVector3(0, kind == .fireflies ? 1.4 : 14, 2)
        env.addChildNode(node)
        weatherNode = node
    }
}
