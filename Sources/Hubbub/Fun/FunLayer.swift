import SceneKit
import SwiftUI

/// Facade the Stage talks to: race overlay + surprise guests + music activation.
@MainActor
final class FunLayer {
    let root = SCNNode()
    let race = RaceOverlay()
    let guests = GuestLayer()
    let halloween = HalloweenLayer()

    init() {
        root.name = "fun"
        root.addChildNode(race.root)
        root.addChildNode(guests.root)
        root.addChildNode(halloween.root)
        MusicCenter.shared.activate()
    }

    /// Render-path hook (never called while the popover is hidden).
    func tick(t: Double, theme: Theme, session: SessionInfo?, sim: RoomSim, stage: Stage) {
        race.tick(t: t, theme: theme, session: session, sim: sim, stage: stage)
        guests.tick(t: t, theme: theme, stage: stage)
        halloween.attach(to: stage.camera)
        halloween.tick(t: t, theme: theme, stage: stage)
    }
}

/// Settings > Appearance card.
struct FunSettingsView: View {
    @AppStorage(RaceOverlay.enabledKey) private var race = false
    @AppStorage(GuestLayer.enabledKey) private var guests = false

    init() { DefaultsMigration.run }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Race mode", "Agents run little races in the foreground; speed follows real activity.") {
                Toggle("Race mode", isOn: $race).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            row("Surprise guests", "Rare visitors on special occasions. Click them for a laugh.") {
                Toggle("Surprise guests", isOn: $guests).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack {
                Spacer()
                Button("Send a guest now") { Stage.current?.sendGuestNow() }.controlSize(.small)
            }
        }
    }

    private func row<C: View>(_ title: String, _ help: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption)
                Text(help).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
    }
}

/// Stage-corner toggle for race mode, styled like the camera button.
struct RaceModeButton: View {
    @AppStorage(RaceOverlay.enabledKey) private var on = false
    var body: some View {
        Button { on.toggle() } label: {
            Image(systemName: "flag.checkered")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(on ? 1 : 0.9))
                .frame(width: 24, height: 24)
                .background(on ? Color.accentColor.opacity(0.85) : Color.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Race mode on (click to stop)" : "Start race mode")
        .accessibilityLabel("Race mode")
        .accessibilityValue(on ? "On" : "Off")
        .padding(.vertical, 8)
        .opacity(0.85)
    }
}

extension Stage {
    func sendGuestNow() { fun.guests.visitNow(t: now, theme: theme, stage: self) }
}

/// `Hubbub --selftest-fun`: race speed maths, guest scheduling and music loop buffers.
@MainActor
enum FunSelfTest {
    static func run() -> Bool {
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }

        // Race speed
        let idle = RaceMath.speed(callsPerMin: 30, tokensPerSec: 100, busy: false)
        let slow = RaceMath.speed(callsPerMin: 0, tokensPerSec: 0, busy: true)
        let mid = RaceMath.speed(callsPerMin: 6, tokensPerSec: 20, busy: true)
        let fast = RaceMath.speed(callsPerMin: 1000, tokensPerSec: 1e6, busy: true)
        check(idle < slow && slow < mid && mid < fast, "speed ordering")
        check(fast <= 0.12 + 1e-9 && RaceMath.speed(callsPerMin: -5, tokensPerSec: -5, busy: true) == slow, "speed bounds")

        // Rates
        var r = RaceRate()
        r.feed(calls: 0, tokens: 0, failures: 0, t: 0)
        let f1 = r.feed(calls: 5, tokens: 1000, failures: 0, t: 5)
        check(!f1 && r.callsPerMin > 0 && r.tokensPerSec > 0, "rate rises")
        let before = r.callsPerMin
        r.feed(calls: 5, tokens: 1000, failures: 0, t: 25)
        check(r.callsPerMin < before, "rate decays when idle")
        check(r.feed(calls: 6, tokens: 1000, failures: 1, t: 30), "failure detected")

        // Race state
        var race = RaceState([RaceRacer(id: "a", name: "A", speed: 0.08), RaceRacer(id: "b", name: "B", speed: 0.05)])
        for _ in 0..<2000 where !race.isOver { race.advance(0.05) }
        check(race.winner == "a" && race.ranking.first?.id == "a", "faster racer wins")
        var stum = RaceState([RaceRacer(id: "a", name: "A", speed: 0.08), RaceRacer(id: "b", name: "B", speed: 0.05)])
        stum.advance(5); stum.stumble("a"); stum.stumble("a")
        check(stum.racers[0].stumbles == 1, "stumble not stackable")
        let pa = stum.racers[0].progress
        stum.advance(1)
        check(stum.racers[0].progress == pa, "stumbling racer stands still")
        var tie = RaceState([RaceRacer(id: "a", name: "A", speed: 0.001)])
        for _ in 0..<1000 { tie.advance(0.1) }
        check(tie.winner == "a", "time limit crowns the leader")
        for th in Theme.allCases {
            check(!RaceText.start(th).isEmpty && RaceText.win(th, name: "X", roll: 0.9).contains("X") && RaceText.stumble(th, name: "Y", roll: 0).contains("Y"), "race text \(th)")
        }

        // Guest scheduling
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        check(GuestPlan.specialDay(date(2026, 2, 13), calendar: cal) == "friday13", "friday 13th")
        check(GuestPlan.specialDay(date(2026, 3, 13), calendar: cal) == "friday13", "friday 13th (march)")
        check(GuestPlan.specialDay(date(2026, 11, 13), calendar: cal) == "friday13", "friday 13th (nov)")
        check(GuestPlan.specialDay(date(2026, 5, 13), calendar: cal) == nil, "wednesday 13th is not special")
        check(GuestPlan.specialDay(date(2027, 1, 1), calendar: cal) == "newyear", "new year")
        check(GuestPlan.specialDay(date(2026, 10, 31), calendar: cal) == "halloween", "halloween")
        check(GuestPlan.specialDay(date(2026, 6, 10), calendar: cal) == nil, "plain day")
        let plain = date(2026, 6, 10), friday = date(2026, 2, 13)
        check(GuestPlan.decide(now: plain, calendar: cal, lastGuestAt: nil, lastSpecialKey: nil, pendingMilestone: nil, roll: 0.5) == nil, "no guest on high roll")
        check(GuestPlan.decide(now: plain, calendar: cal, lastGuestAt: nil, lastSpecialKey: nil, pendingMilestone: nil, roll: 0.001) == .random, "random guest on low roll")
        check(GuestPlan.decide(now: plain, calendar: cal, lastGuestAt: plain.addingTimeInterval(-300), lastSpecialKey: nil, pendingMilestone: nil, roll: 0.001) == nil, "random gap respected")
        check(GuestPlan.decide(now: plain, calendar: cal, lastGuestAt: plain.addingTimeInterval(-10), lastSpecialKey: nil, pendingMilestone: 10, roll: 0.001) == nil, "min gap respected")
        check(GuestPlan.decide(now: plain, calendar: cal, lastGuestAt: nil, lastSpecialKey: nil, pendingMilestone: 20, roll: 0.9) == .milestone(20), "milestone guest")
        check(GuestPlan.decide(now: friday, calendar: cal, lastGuestAt: nil, lastSpecialKey: nil, pendingMilestone: nil, roll: 0.9) == .special("friday13"), "special guest")
        let key = GuestPlan.dayKey("friday13", friday, calendar: cal)
        check(GuestPlan.decide(now: friday, calendar: cal, lastGuestAt: nil, lastSpecialKey: key, pendingMilestone: nil, roll: 0.9) == nil, "special once per day")
        check(GuestPlan.kind(for: .special("friday13"), theme: .space, roll: 0.3) == .ghost, "ghost on friday 13th")
        check(GuestPlan.kind(for: .special("newyear"), theme: .farm, roll: 0.3) == .partyPal, "party pal on new year")
        for th in Theme.allCases {
            let pool = GuestPlan.pool(th)
            check(!pool.isEmpty && pool.contains(GuestPlan.kind(for: .random, theme: th, roll: 0.0)) && pool.contains(GuestPlan.kind(for: .random, theme: th, roll: 0.999)), "pool \(th)")
            check(!GuestPlan.quip(th).isEmpty, "quip \(th)")
        }
        for k in GuestKind.allCases { check(k.clickLines.count >= 3 && !k.arrival.isEmpty && !k.leaveLine.isEmpty, "guest lines \(k)") }

        // Music loops
        check(MusicCenter.shouldPlay(enabled: true, visible: true, lowPower: false), "plays when allowed")
        check(!MusicCenter.shouldPlay(enabled: true, visible: false, lowPower: false), "pauses when hidden")
        check(!MusicCenter.shouldPlay(enabled: true, visible: true, lowPower: true), "pauses in low power mode")
        check(!MusicCenter.shouldPlay(enabled: false, visible: true, lowPower: false), "off by default")
        for th in Theme.allCases {
            let spec = MusicSynth.spec(for: th)
            let buf = MusicSynth.render(spec)
            let s = MusicSynth.stats(buf)
            check(buf.count == MusicSynth.frameCount(spec) && buf.count > 22050 * 8, "music length \(th)")
            check(s.finite && s.peak > 0.3 && s.peak <= 0.61, "music peak \(th) \(s.peak)")
            check(s.rms > 0.02 && s.rms < 0.4, "music rms \(th) \(s.rms)")
            check(s.seam < 0.35, "music seam \(th) \(s.seam)")
            let tail = buf.suffix(2205).reduce(Float(0)) { max($0, abs($1)) }, head = buf.prefix(2205).reduce(Float(0)) { max($0, abs($1)) }
            check(tail > 0 && head > 0, "music edges alive \(th)")
        }

        print(failures.isEmpty ? "fun selftest OK" : "fun selftest FAILED:\n  " + failures.joined(separator: "\n  "))
        return failures.isEmpty
    }
}
