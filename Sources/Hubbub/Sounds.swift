import AppKit
import AVFoundation
import SwiftUI

/// Optional event sounds (default off). Short tones are synthesised on demand, so nothing runs while idle.
@MainActor
final class SoundCenter {
    static let shared = SoundCenter()
    enum Kind: String, CaseIterable { case spawn, success, failure, alert }

    static let enabledKey = "sfxEnabled"
    static let volumeKey = "sfxVolume"

    private var lastPlay = Date.distantPast
    private var cache: [String: AVAudioPlayer] = [:]

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    var volume: Float { Float(UserDefaults.standard.object(forKey: Self.volumeKey) as? Double ?? 0.5) }

    /// `force` skips the enabled/visibility/rate-limit checks (used by the Test button).
    func play(_ kind: Kind, force: Bool = false) {
        if !force {
            guard enabled else { return }
            guard kind == .alert || Stage.popoverVisible else { return }
            guard Date().timeIntervalSince(lastPlay) >= 0.4 else { return }
        }
        lastPlay = Date()
        let theme = Theme.resolve(UserDefaults.standard.string(forKey: "theme") ?? "")
        if let data = Self.synth(kind, theme) {
            let key = "\(theme.rawValue)/\(kind.rawValue)"
            let p = cache[key] ?? (try? AVAudioPlayer(data: data))
            if let p {
                cache[key] = p
                p.volume = volume
                p.currentTime = 0
                p.play()
                return
            }
        }
        let name: String
        switch kind {
        case .spawn: name = "Pop"
        case .success: name = "Glass"
        case .failure: name = "Basso"
        case .alert: name = "Funk"
        }
        if let s = NSSound(named: NSSound.Name(name)) { s.volume = volume; s.play() }
    }

    // MARK: synthesis

    /// Theme flavours; nil falls back to a system sound.
    nonisolated static func synth(_ kind: Kind, _ theme: Theme) -> Data? {
        switch (theme, kind) {
        case (.kitchen, .success): return wav(tone(freq: { _ in 1760 }, dur: 0.6, decay: 5))
        case (.kitchen, .spawn): return wav(tone(freq: { _ in 988 }, dur: 0.15, decay: 14))
        case (.football, .failure): return wav(tone(freq: { _ in 2900 }, dur: 0.55, decay: 1, trem: 28, attack: 0.02))
        case (.football, .success): return wav(tone(freq: { $0 < 0.12 ? 880 : 1320 }, dur: 0.3, decay: 4))
        case (.farm, .failure): return wav(tone(freq: { 320 - 90 * $0 + 12 * sin($0 * 60) }, dur: 0.6, decay: 2, saw: true))
        case (.farm, .spawn): return wav(tone(freq: { 420 - 60 * $0 }, dur: 0.18, decay: 8, saw: true))
        case (.impostor, _): return impostorSynth(kind)
        case (.wizard, _): return wizardSynth(kind)
        case (.galactic, _): return galacticSynth(kind)
        case (.fellowship, _): return fellowshipSynth(kind)
        default: return nil
        }
    }

    /// Mono 22.05 kHz samples; `freq` receives time in seconds.
    nonisolated static func tone(freq: (Double) -> Double, dur: Double, decay: Double, trem: Double = 0,
                                 attack: Double = 0.005, saw: Bool = false) -> [Float] {
        let rate = 22050.0
        var phase = 0.0
        return (0..<Int(dur * rate)).map { i in
            let t = Double(i) / rate
            phase += 2 * .pi * freq(t) / rate
            var v = saw ? (phase / .pi).truncatingRemainder(dividingBy: 2) - 1 : sin(phase)
            if saw { v *= 0.6 }
            let env = min(1, t / attack) * exp(-decay * t / dur) * min(1, (dur - t) / 0.02)
            let am = trem > 0 ? 0.65 + 0.35 * sin(2 * .pi * trem * t) : 1
            return Float(v * env * am * 0.8)
        }
    }

    nonisolated static func wav(_ s: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + s.count * 2))
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(22050); u32(44100); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(s.count * 2))
        for f in s { u16(UInt16(bitPattern: Int16(max(-1, min(1, f)) * 32000))) }
        return d
    }
}

/// Settings section: toggle, volume and a test button.
struct SoundSettingsView: View {
    @AppStorage(SoundCenter.enabledKey) private var on = false
    @AppStorage(SoundCenter.volumeKey) private var volume = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Event sounds (spawn, success, failure)", isOn: $on).toggleStyle(.switch).controlSize(.small)
            if on {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption)
                    Slider(value: $volume, in: 0...1).frame(maxWidth: 160)
                    Button("Test sound") {
                        SoundCenter.shared.play(.success, force: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { SoundCenter.shared.play(.failure, force: true) }
                    }.controlSize(.small)
                }
                Text("Sounds follow the theme and play only while the popover is open.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
