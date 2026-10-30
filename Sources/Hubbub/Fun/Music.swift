import AVFoundation
import Foundation
import SwiftUI

// Original synthesized theme music: generative chiptune loops and slow pads, rendered once per theme into a seamless buffer.

enum MusicWave { case sine, tri, saw, pluck, square(Double) }

struct MusicSpec {
    enum Style { case chip, pad }
    var style: Style
    var bpm: Double
    var bars = 8
    var root: Int
    var scale: [Int]
    var progression: [Int]
    var lead: MusicWave
    var bass: MusicWave = .tri
    var drums = false
    var density = 0.5
    var seed: UInt64
}

enum MusicSynth {
    static let rate = 22050.0
    private static let minorPent = [0, 3, 5, 7, 10], majorPent = [0, 2, 4, 7, 9]
    private static let major = [0, 2, 4, 5, 7, 9, 11], minor = [0, 2, 3, 5, 7, 8, 10]
    private static let dorian = [0, 2, 3, 5, 7, 9, 10], mixolydian = [0, 2, 4, 5, 7, 9, 10], locrianish = [0, 1, 3, 5, 6, 8, 10]

    static func spec(for theme: Theme) -> MusicSpec {
        if let s = ThemeExtensions.active?.music(theme) { return s }
        return switch theme {
        case .kitchen: MusicSpec(style: .chip, bpm: 116, root: 60, scale: majorPent, progression: [0, 3, 4, 0, 0, 3, 4, 2], lead: .square(0.5), density: 0.55, seed: 11)
        case .prison: MusicSpec(style: .chip, bpm: 84, root: 48, scale: minor, progression: [0, 0, 5, 5, 3, 3, 4, 4], lead: .square(0.125), bass: .saw, density: 0.3, seed: 23)
        case .football: MusicSpec(style: .chip, bpm: 126, root: 60, scale: major, progression: [0, 3, 4, 0, 0, 3, 4, 4], lead: .square(0.5), drums: true, density: 0.6, seed: 37)
        case .farm: MusicSpec(style: .pad, bpm: 88, root: 55, scale: majorPent, progression: [0, 3, 4, 3, 0, 2, 4, 3], lead: .pluck, density: 0.45, seed: 41)
        case .impostor: MusicSpec(style: .chip, bpm: 96, root: 50, scale: locrianish, progression: [0, 0, 1, 0, 0, 0, 4, 1], lead: .tri, bass: .square(0.5), density: 0.3, seed: 53)
        case .wizard: MusicSpec(style: .pad, bpm: 72, root: 52, scale: dorian, progression: [0, 3, 4, 0, 5, 3, 1, 0], lead: .pluck, density: 0.4, seed: 67)
        case .galactic: MusicSpec(style: .chip, bpm: 124, root: 57, scale: mixolydian, progression: [0, 6, 3, 4, 0, 6, 3, 4], lead: .saw, bass: .saw, drums: true, density: 0.6, seed: 71)
        case .fellowship: MusicSpec(style: .pad, bpm: 62, root: 50, scale: minor, progression: [0, 5, 3, 4, 0, 5, 6, 4], lead: .sine, density: 0.3, seed: 83)
        default: MusicSpec(style: .pad, bpm: 64, root: 45, scale: minorPent, progression: [0, 3, 2, 4, 0, 3, 1, 2], lead: .pluck, density: 0.35, seed: 97)
        }
    }

    static func frameCount(_ s: MusicSpec) -> Int { Int((Double(s.bars) * 4 * 60 / s.bpm * rate).rounded()) }

    private struct RNG {
        var s: UInt64
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double((s >> 33) & 0xFFFFFF) / Double(0x1000000)
        }
    }

    private static func freq(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    private static func midi(_ spec: MusicSpec, degree: Int) -> Double {
        let n = spec.scale.count
        let oct = Int((Double(degree) / Double(n)).rounded(.down))
        return Double(spec.root + spec.scale[degree - oct * n] + 12 * oct)
    }

    private static func osc(_ w: MusicWave, _ phase: Double, _ t: Double, _ decay: Double) -> Double {
        let p = phase.truncatingRemainder(dividingBy: 1)
        switch w {
        case .sine: return sin(2 * .pi * phase)
        case .tri: return 4 * abs(p - 0.5) - 1
        case .saw: return (2 * p - 1) * 0.6
        case .square(let duty): return (p < duty ? 1 : -1) * 0.55
        case .pluck: return (sin(2 * .pi * phase) + 0.35 * sin(4 * .pi * phase) + 0.12 * sin(6 * .pi * phase)) * exp(-decay * t)
        }
    }

    /// Mono loop. Notes wrap around the end, so the tail rings into the start and the seam is clean.
    static func render(_ spec: MusicSpec) -> [Float] {
        let n = frameCount(spec)
        var buf = [Double](repeating: 0, count: n)
        let beat = 60 / spec.bpm
        let loopSec = Double(n) / rate
        var rng = RNG(s: spec.seed)

        func add(_ start: Double, _ dur: Double, _ f: Double, _ w: MusicWave, _ amp: Double, attack: Double = 0.01,
                 release: Double = 0.08, decay: Double = 6, lfo: Bool = false) {
            let s0 = ((Int((start * rate).rounded()) % n) + n) % n
            let len = Int((dur + release) * rate)
            var phase = 0.0
            let step = f / rate
            let lfoHz = max(1, (0.25 * loopSec).rounded()) / loopSec
            for i in 0..<len {
                let t = Double(i) / rate
                var env = min(1, t / attack)
                if t > dur { env *= max(0, 1 - (t - dur) / release) }
                var v = osc(w, phase, t, decay) * env * amp
                if lfo { v *= 1 + 0.18 * sin(2 * .pi * lfoHz * (start + t)) }
                buf[(s0 + i) % n] += v
                phase += step
            }
        }

        let barLen = 4 * beat
        func chordDegrees(_ bar: Int) -> [Int] { let d = spec.progression[bar % spec.progression.count]; return [d, d + 2, d + 4] }

        // Two 2-bar melodic phrases; the loop plays them A A B A, so it sounds composed rather than random.
        func phrase() -> [(slot: Int, deg: Int, len: Int)] {
            var out: [(Int, Int, Int)] = []
            var deg = spec.scale.count + 1
            var slot = 0
            while slot < 16 {
                if rng.next() < spec.density || slot % 8 == 0 {
                    deg = max(spec.scale.count - 1, min(spec.scale.count * 2 + 1, deg + Int(rng.next() * 5) - 2))
                    let len = rng.next() < 0.35 ? 2 : 1
                    out.append((slot, deg, len))
                    slot += len
                } else { slot += 1 }
            }
            return out
        }
        let a = phrase(), b = phrase()
        let order = [a, a, b, a]

        switch spec.style {
        case .chip:
            for bar in 0..<spec.bars {
                let t0 = Double(bar) * barLen
                let chord = chordDegrees(bar)
                for e in 0..<8 {
                    let f = freq(midi(spec, degree: chord[e % 3] + spec.scale.count))
                    add(t0 + Double(e) * beat / 2, beat / 2 * 0.8, f, .square(0.25), 0.045, attack: 0.004, release: 0.03)
                }
                for q in 0..<4 {
                    let bf = freq(midi(spec, degree: chord[0] - spec.scale.count))
                    add(t0 + Double(q) * beat, beat * 0.85, bf, spec.bass, 0.16, attack: 0.006, release: 0.05)
                }
                if spec.drums {
                    for q in 0..<4 { add(t0 + Double(q) * beat, 0.12, 70 + 30 * Double(q % 2), .sine, 0.2, attack: 0.002, release: 0.05) }
                }
                for e in 0..<8 where e % 2 == 1 { hat(&buf, n, t0 + Double(e) * beat / 2, &rng) }
            }
            for (p, ph) in order.enumerated() {
                for note in ph {
                    let t0 = Double(p) * 2 * barLen + Double(note.slot) * beat / 2
                    add(t0, Double(note.len) * beat / 2 * 0.9, freq(midi(spec, degree: note.deg)), spec.lead, 0.09, attack: 0.006, release: 0.05)
                }
            }
        case .pad:
            for bar in 0..<spec.bars {
                let t0 = Double(bar) * barLen
                for (i, d) in chordDegrees(bar).enumerated() {
                    let m = midi(spec, degree: d)
                    for cents in [-4.0, 0, 4.0] {
                        add(t0 - 0.4, barLen + 0.4, freq(m + cents / 100), .sine, 0.045 - Double(i) * 0.005, attack: 1.3, release: 1.6, lfo: true)
                    }
                }
                add(t0, barLen, freq(midi(spec, degree: chordDegrees(bar)[0] - spec.scale.count)), .sine, 0.09, attack: 0.8, release: 1.2)
            }
            for (p, ph) in order.enumerated() {
                for note in ph where note.slot % 2 == 0 {
                    let t0 = Double(p) * 2 * barLen + Double(note.slot) * beat / 2
                    let held = spec.lead.isSustained
                    add(t0, held ? beat * 1.6 : 0.2, freq(midi(spec, degree: note.deg + spec.scale.count)), spec.lead, held ? 0.05 : 0.07,
                        attack: held ? 0.25 : 0.006, release: held ? 0.9 : 0.5, decay: 3.2)
                }
            }
        }

        let peak = buf.reduce(0) { max($0, abs($1)) }
        let gain = peak > 0 ? 0.6 / peak : 1
        return buf.map { Float($0 * gain) }
    }

    private static func hat(_ buf: inout [Double], _ n: Int, _ start: Double, _ rng: inout RNG) {
        let s0 = Int(start * rate)
        for i in 0..<Int(0.04 * rate) {
            let env = exp(-Double(i) / (0.008 * rate))
            buf[(s0 + i) % n] += (rng.next() * 2 - 1) * env * 0.035
        }
    }

    /// Quick sanity metrics used by `--selftest-fun`.
    static func stats(_ s: [Float]) -> (peak: Float, rms: Float, seam: Float, finite: Bool) {
        var peak: Float = 0, sum: Float = 0, ok = true
        for v in s { if !v.isFinite { ok = false }; peak = max(peak, abs(v)); sum += v * v }
        let seam = s.isEmpty ? 0 : abs(s[0] - s[s.count - 1])
        return (peak, s.isEmpty ? 0 : (sum / Float(s.count)).squareRoot(), seam, ok)
    }
}

private extension MusicWave {
    var isSustained: Bool { if case .sine = self { return true } else { return false } }
}

/// Plays the loop for the current theme. Default off; stops completely while the popover is hidden or Low Power Mode is on.
@MainActor
final class MusicCenter {
    static let shared = MusicCenter()
    static let enabledKey = "musicEnabled"
    static let volumeKey = "musicVolume"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var attached = false
    private var playingTheme: Theme?
    private var rendering: Theme?
    private var cache: (theme: Theme, buffer: AVAudioPCMBuffer)?
    private var observing = false
    private var fadeToken = 0

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var volume: Float { Float(UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 0.35) }
    var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    nonisolated static func shouldPlay(enabled: Bool, visible: Bool, lowPower: Bool) -> Bool { enabled && visible && !lowPower }

    var theme: Theme {
        CustomThemes.active?.baseTheme ?? Theme.resolve(UserDefaults.standard.string(forKey: "theme") ?? "")
    }

    /// Registers observers once; nothing runs (and no audio hardware is touched) while the music is off.
    func activate() {
        guard !observing else { return }
        observing = true
        let nc = NotificationCenter.default
        let hop: (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.reconcile() } }
        nc.addObserver(forName: Stage.visibilityChanged, object: nil, queue: .main, using: hop)
        nc.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main, using: hop)
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: hop)
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playingTheme = nil; self?.reconcile() }
        }
        reconcile()
    }

    /// Why the music is silent although it is enabled.
    var pauseReason: String? {
        guard enabled else { return nil }
        if lowPower { return "Paused while Low Power Mode is on." }
        return Stage.popoverVisible ? nil : "Paused while Hubbub is hidden."
    }

    func reconcile() {
        let want = Self.shouldPlay(enabled: enabled, visible: Stage.popoverVisible, lowPower: lowPower)
        guard want else {
            if playingTheme != nil || engine.isRunning { stop() }
            return
        }
        let th = theme
        if playingTheme == th, engine.isRunning, player.isPlaying {
            player.volume = volume
        } else {
            start(th)
        }
    }

    private func start(_ th: Theme) {
        if let c = cache, c.theme == th { play(c.buffer, th); return }
        guard rendering != th else { return }
        rendering = th
        let spec = MusicSynth.spec(for: th)
        Task.detached(priority: .utility) {
            let samples = MusicSynth.render(spec)
            await MainActor.run { MusicCenter.shared.finishRender(th, samples) }
        }
    }

    private func finishRender(_ th: Theme, _ samples: [Float]) {
        rendering = nil
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: MusicSynth.rate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        cache = (th, buf)
        reconcile()
    }

    private func play(_ buf: AVAudioPCMBuffer, _ th: Theme) {
        player.stop()
        engine.stop()
        if !attached { engine.attach(player); attached = true }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: buf.format)
        do { try engine.start() } catch { return }
        player.volume = 0
        player.scheduleBuffer(buf, at: nil, options: .loops)
        player.play()
        playingTheme = th
        fadeIn()
    }

    private func fadeIn() {
        fadeToken += 1
        let token = fadeToken
        for i in 1...6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(i)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.fadeToken == token, self.player.isPlaying else { return }
                    self.player.volume = self.volume * Float(i) / 6
                }
            }
        }
    }

    private func stop() {
        fadeToken += 1
        player.stop()
        engine.stop()
        playingTheme = nil
    }
}

/// Settings > Sound: toggle, volume and status for the generated theme music.
struct MusicSettingsView: View {
    @AppStorage(MusicCenter.enabledKey) private var on = false
    @AppStorage(MusicCenter.volumeKey) private var volume = 0.35

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Theme music", isOn: $on).toggleStyle(.switch).controlSize(.small)
            if on {
                HStack(spacing: 8) {
                    Image(systemName: "music.note").font(.caption)
                    Slider(value: $volume, in: 0...1).frame(maxWidth: 160)
                }
                Text(MusicCenter.shared.pauseReason ?? "A soft loop that matches the theme, synthesised on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { MusicCenter.shared.activate() }
    }
}
