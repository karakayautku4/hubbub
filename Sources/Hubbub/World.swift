import SwiftUI

enum Phase { case arriving, working, onBreak, chatting, finishing, leaving }
enum Mood { case none, panic, celebrate, tired, chat, sip, dizzy, sleep, dragged, sad, sick, card }
enum Carry { case plate, cup, papers, ball, card }
enum SimEvent { case failure, finished(String), tired, spawned }

struct Actor: Identifiable {
    let id: String
    var name: String
    var model: String
    var startedAt: Date
    var isCaptain: Bool
    var variant: Int
    var pos: CGPoint
    var route: [CGPoint] = []
    var heading: CGFloat = 0
    var walked: CGFloat = 0
    var phase: Phase = .working
    var station: Int?
    var kind = 0
    var slot = 0
    var pauseUntil: Double = 0
    var mood: Mood = .none
    var moodUntil: Double = 0
    var say: String?
    var sayUntil: Double = 0
    var carry: Carry?
    var tool: String?
    var busy = false
    var dragged = false
    var actions: [ActionRecord] = []
    var stationSince: Double = 0
    var nextTalk: Double = 0
    var breakAt: Double = 0
    var lastSwitch: Double = 0
    var chatPartner: String?
    var pending: String?
    var carded = false
    var ctx: Double = 0
    var cost: Double = 0
    var costSeen = false
    var costEvents = 0
    var costDelta: Double = 0
    var compactEvents = 0
    var approval = false
    var success: Double = 1
    var calls = 0
    var ageSec: Double = 0
    var spawnAt: Double = 0
    /// Index into `Jobs.slots(for:)`; -1 until assigned.
    var jobSlot = -1
    /// True while the agent's current destination is its job spot (no tool running).
    var onJob = false
    /// True while the agent stands at its job spot and should play the job animation.
    var atJob = false

    var moving: Bool { !route.isEmpty }
}

/// Simulation of one session's room: decides where every character walks and how it feels.
/// Positions are in logical 320x180 coordinates; Stage converts them to 3D world space.
final class RoomSim {
    private(set) var theme: Theme
    var captain: Actor
    var subs: [Actor] = []
    private var events: [SimEvent] = []
    var pendingEffects: [SceneEffect] = []
    var spawnQueue: [String] = []
    var workingSince: Double?
    private var patrolIndex = 0
    private var handledFailure: Date?
    private var nextChatAt: Double = 0
    private var lastCaptainTool: String?

    init(theme: Theme) {
        self.theme = theme
        captain = RoomSim.makeCaptain(theme)
        captain.jobSlot = Jobs.pickSlot(id: captain.id, taken: [], theme: theme)
    }

    private static func makeCaptain(_ theme: Theme) -> Actor {
        Actor(id: "captain", name: theme.captainRole, model: "", startedAt: Date(), isCaptain: true, variant: 0, pos: theme.post)
    }

    var all: [Actor] { subs + [captain] }

    func drainEvents() -> [SimEvent] {
        defer { events = [] }
        return events
    }

    // MARK: Interaction

    func send(captainTo p: CGPoint, t: Double) {
        guard !captain.dragged else { return }
        captain.route = [clamp(p)]
        captain.onJob = false
        captain.pauseUntil = t + 9
        captain.chatPartner = nil
    }

    func say(_ id: String, _ text: String, t: Double, duration: Double = 2.6) {
        mutate(id) { $0.say = text; $0.sayUntil = t + duration }
    }

    func beginDrag(_ id: String, t: Double) {
        mutate(id) {
            $0.dragged = true
            $0.route = []
            $0.mood = .dragged
            $0.moodUntil = .infinity
            $0.say = "Whoa!"
            $0.sayUntil = .infinity
        }
    }

    func drag(_ id: String, to p: CGPoint) {
        mutate(id) { $0.pos = clamp(p) }
    }

    func drop(_ id: String, t: Double) {
        guard let a = all.first(where: { $0.id == id }) else { return }
        let target: CGPoint? = a.isCaptain ? nil : home(of: a)
        mutate(id) {
            $0.dragged = false
            $0.mood = .dizzy
            $0.moodUntil = t + 1.8
            $0.say = "Hey, put me down!"
            $0.sayUntil = t + 2.2
            if $0.isCaptain {
                $0.pauseUntil = t + 3
            } else if let target, $0.phase == .working || $0.phase == .arriving || $0.phase == .chatting {
                $0.phase = .arriving
                $0.route = [target]
            }
        }
    }

    func panicAll(t: Double, line: String? = nil) {
        for a in all where a.phase != .leaving {
            mutate(a.id) {
                $0.mood = .panic
                $0.moodUntil = t + 3
                $0.say = line ?? theme.panicLine
                $0.sayUntil = t + 3
            }
        }
    }

    func cheerAll(t: Double, line: String) {
        for a in all where a.phase != .leaving {
            mutate(a.id) {
                $0.mood = .celebrate
                $0.moodUntil = t + 2
                $0.say = line
                $0.sayUntil = t + 2.4
            }
        }
    }

    func mutate(_ id: String, _ body: (inout Actor) -> Void) {
        if id == "captain" { body(&captain) }
        else if let i = subs.firstIndex(where: { $0.id == id }) { body(&subs[i]) }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, -230), 550), y: min(max(p.y, 102), 200))
    }

    // MARK: Jobs

    var jobSlots: [JobSlot] { Jobs.slots(for: theme) }

    func jobSpot(_ a: Actor) -> CGPoint {
        let s = jobSlots
        return s[min(max(a.jobSlot, 0), s.count - 1)].pos
    }

    func job(of a: Actor) -> Job? {
        let s = jobSlots
        guard s.indices.contains(a.jobSlot) else { return nil }
        let jobs = Jobs.catalog(for: theme)
        return jobs[s[a.jobSlot].jobIndex % jobs.count]
    }

    /// Where an agent belongs when nothing else is going on: its job spot, or its tool station while a tool runs.
    func home(of a: Actor) -> CGPoint { a.onJob ? jobSpot(a) : stationTarget(a.station ?? 0, excluding: a.id) }

    private func takenSlots(excluding id: String) -> Set<Int> {
        Set(all.filter { $0.id != id && $0.phase != .leaving }.map(\.jobSlot))
    }

    private var lastCompact = 0.0

    /// Keeps the occupied area small after agents leave: the outermost agent moves into the lowest free slot.
    private func compactJobs(t: Double) {
        guard t - lastCompact > 5 else { return }
        lastCompact = t
        let live = all.filter { $0.phase != .leaving && !$0.dragged }
        guard let far = live.max(by: { $0.jobSlot < $1.jobSlot }), far.jobSlot > live.count + 3 else { return }
        let taken = takenSlots(excluding: far.id)
        guard let free = (0..<jobSlots.count).first(where: { !taken.contains($0) }), free < far.jobSlot else { return }
        mutate(far.id) {
            $0.jobSlot = free
            if $0.onJob, $0.phase == .working || $0.phase == .arriving { $0.route = [jobSpot($0)]; $0.phase = $0.isCaptain ? $0.phase : .arriving }
        }
    }

    // MARK: Update

    func update(session: SessionInfo?, theme newTheme: Theme, t: Double, dt: Double) {
        if newTheme != theme {
            theme = newTheme
            subs = []
            captain = RoomSim.makeCaptain(theme)
            captain.jobSlot = Jobs.pickSlot(id: captain.id, taken: [], theme: theme)
        }
        let state = session?.state ?? .offline
        captain.name = theme.captainRole
        captain.model = session?.model ?? ""
        captain.actions = session?.actions ?? []
        captain.tool = session?.currentTool
        if let session { applyMetrics(&captain, ctx: session.contextFraction, cost: session.costCredits, approval: session.waitingApproval, success: session.successRate, calls: session.toolCalls, t: t) }
        captain.ageSec = session?.age ?? 0
        var current = session?.subagents ?? []
        if let f = fakeSub, t < fakeUntil, !current.contains(where: { $0.id == f.id }) { current.append(f) }
        syncSubs(current, t: t)
        emitSceneEffects(state: state, t: t)
        checkFailure(session, t: t)

        for i in subs.indices {
            var a = subs[i]
            updateSub(&a, t: t)
            advance(&a, speed: 46, dt: dt, t: t)
            subs[i] = a
        }
        subs.removeAll { $0.phase == .leaving && !$0.moving }
        separate(t: t)
        scheduleChat(t: t)
        updateCaptain(state: state, t: t)
        var cap = captain
        advance(&cap, speed: 38, dt: dt, t: t)
        captain = cap
        compactJobs(t: t)
        for i in subs.indices { subs[i].atJob = !subs[i].moving && dist(subs[i].pos, jobSpot(subs[i])) < 3 }
        captain.atJob = !captain.moving && dist(captain.pos, jobSpot(captain)) < 3
    }

    /// Nudges walking characters apart so they never stack on top of each other.
    /// True when nobody nearby is already talking, so ambient chatter doesn't pile up.
    private func quietAround(_ a: Actor) -> Bool {
        let all = subs + [captain]
        return !all.contains { $0.id != a.id && $0.say != nil && hypot($0.pos.x - a.pos.x, $0.pos.y - a.pos.y) < 60 }
    }

    private func separate(t: Double) {
        let minDist: CGFloat = 13
        for i in subs.indices {
            guard subs[i].moving, !subs[i].dragged, t >= subs[i].spawnAt else { continue }
            for j in subs.indices where j != i && !subs[j].dragged && t >= subs[j].spawnAt {
                let dx = subs[i].pos.x - subs[j].pos.x, dy = subs[i].pos.y - subs[j].pos.y
                let d = max(hypot(dx, dy), 0.01)
                guard d < minDist else { continue }
                let push = (minDist - d) * (subs[j].moving ? 0.15 : 0.3)
                subs[i].pos.x += dx / d * push
                subs[i].pos.y += dy / d * push
            }
        }
    }

    private var lastSpawnAt = 0.0
    private var fakeSub: SubAgent?
    private var fakeUntil = 0.0

    /// Debug: trigger the theme's failure effect now, adding a temporary sub-agent if none is working.
    func simulateFailure(t: Double) {
        if victim() == nil {
            fakeSub = SubAgent(id: "debug-fake", name: "debug", displayName: "debug", model: "test", startedAt: Date().addingTimeInterval(-20), tool: "bash", busy: true)
            fakeUntil = t + 25
            addSub(fakeSub!, t: t)
        }
        switch theme {
        case .football: redCard(t: t)
        case .farm: sickSheep(t: t)
        case .impostor: impostorFailure(t: t)
        case .wizard: wizardFailure(t: t)
        case .galactic: galacticFailure(t: t)
        case .fellowship: fellowshipFailure(t: t)
        default: panicAll(t: t)
        }
        events.append(.failure)
        emit(.failure(failureSpot()))
    }

    private func checkFailure(_ session: SessionInfo?, t: Double) {
        guard let f = session?.lastFailureAt, f != handledFailure else { return }
        handledFailure = f
        if Date().timeIntervalSince(f) < 8 {
            switch theme {
            case .football: redCard(t: t)
            case .farm: sickSheep(t: t)
            case .impostor: impostorFailure(t: t)
            case .wizard: wizardFailure(t: t)
            case .galactic: galacticFailure(t: t)
            case .fellowship: fellowshipFailure(t: t)
            default: panicAll(t: t)
            }
            events.append(.failure)
            emit(.failure(failureSpot()))
        }
    }

    func victim() -> Actor? {
        let pool = subs.filter { [.working, .arriving, .chatting].contains($0.phase) && !$0.dragged }
        return pool.filter(\.busy).randomElement() ?? pool.randomElement()
    }

    /// Referee runs to a player and shows a red card; the player trudges off to the bench.
    private func redCard(t: Double) {
        guard let v = victim() else {
            say("captain", "Foul! 🟨", t: t)
            return
        }
        captain.pending = v.id
        captain.chatPartner = nil
        captain.route = [CGPoint(x: v.pos.x + (v.pos.x > 160 ? 14 : -14), y: v.pos.y + 4)]
        captain.pauseUntil = t + 1
        captain.mood = .none
        captain.say = "Foul! 🏃💨"
        captain.sayUntil = t + 2
        for s in subs where s.id != v.id { mutate(s.id) { $0.say = "Ref!?"; $0.sayUntil = t + 2.2 } }
    }


    /// One sheep gets sick (turns green); the farmer runs over with medicine.
    private func sickSheep(t: Double) {
        for s in subs where s.phase != .leaving {
            mutate(s.id) { $0.mood = .panic; $0.moodUntil = t + 1.8; $0.say = "Baa?! 😨"; $0.sayUntil = t + 2 }
        }
        guard let v = victim() else { return }
        mutate(v.id) { $0.mood = .sick; $0.moodUntil = t + 14; $0.say = "Baa… 🤢"; $0.sayUntil = t + 4 }
        captain.pending = v.id
        captain.chatPartner = nil
        captain.route = [CGPoint(x: v.pos.x + (v.pos.x > 160 ? 14 : -14), y: v.pos.y + 4)]
        captain.pauseUntil = t + 1
        captain.say = "Hang on, I'm coming!"
        captain.sayUntil = t + 2.4
    }

    private func updateSub(_ a: inout Actor, t: Double) {
        if a.dragged { return }
        if a.mood != .none, t >= a.moodUntil { a.mood = .none }
        if a.say != nil, t >= a.sayUntil + 1.0 { a.say = nil }

        switch a.phase {
        case .working:
            let k = Theme.toolKind(a.tool)
            if a.busy {
                if a.onJob || (k != a.kind && t - a.lastSwitch > 2) {
                    a.onJob = false
                    a.kind = k
                    a.lastSwitch = t
                    a.station = k
                    a.route = [stationTarget(k, excluding: a.id)]
                    a.phase = .arriving
                    return
                }
            } else if !a.onJob, t - a.lastSwitch > 6 {
                a.onJob = true
                a.lastSwitch = t
                a.route = [jobSpot(a)]
                a.phase = .arriving
                return
            }
            if t > a.breakAt, t - a.stationSince > 40, !a.busy {
                a.phase = .onBreak
                a.mood = .tired
                a.moodUntil = t + 6
                a.say = theme.tiredLine
                a.sayUntil = t + 3
                a.route = [theme.coffee]
                a.pauseUntil = 0
                events.append(.tired)
                return
            }
            if t > a.nextTalk, a.say == nil, a.mood == .none, quietAround(a) {
                a.say = (a.onJob ? job(of: a)?.lines : nil)?.randomElement() ?? theme.chatter(kind: a.kind).randomElement()
                a.sayUntil = t + 2.8
                a.nextTalk = t + Double.random(in: a.onJob ? 9...20 : 14...28)
            }
        case .onBreak:
            if !a.moving, a.pauseUntil > 0, t >= a.pauseUntil {
                a.carry = nil
                a.mood = .none
                a.pauseUntil = 0
                a.breakAt = t + Double.random(in: 90...160)
                a.phase = .arriving
                a.route = [home(of: a)]
            }
        case .chatting:
            if !a.moving, a.pauseUntil > 0, t >= a.pauseUntil {
                let partner = a.chatPartner
                a.pauseUntil = 0
                a.mood = .none
                a.chatPartner = nil
                a.phase = .arriving
                a.route = [home(of: a)]
                if let partner { mutate(partner) { $0.mood = .none } }
            }
        case .finishing:
            if t >= a.moodUntil {
                a.phase = .leaving
                a.mood = .none
                a.route = [theme.exit]
            }
        case .arriving, .leaving:
            break
        }
    }

    private func updateCaptain(state: SessionState, t: Double) {
        if captain.dragged { return }
        if captain.say != nil, t >= captain.sayUntil + 1.0 { captain.say = nil }
        if captain.mood != .none, captain.mood != .sleep, t >= captain.moodUntil {
            captain.mood = .none
            captain.carry = nil
        }
        if state == .offline {
            captain.mood = .sleep
            if !captain.moving, t >= captain.pauseUntil, dist(captain.pos, theme.post) > 2 { captain.route = [theme.post] }
            return
        }
        if captain.mood == .sleep { captain.mood = .none }

        guard !captain.moving, t >= captain.pauseUntil else { return }
        let spot = jobSpot(captain)
        let atJob = dist(captain.pos, spot) < 3
        let wander = !atJob || Int.random(in: 0..<10) < 3
        if state == .working, wander, atJob || Int.random(in: 0..<10) < 4, let w = subs.filter({ $0.phase == .working && $0.mood == .none }).randomElement() {
            captain.onJob = false
            captain.chatPartner = w.id
            captain.route = [CGPoint(x: w.pos.x + (w.pos.x > 160 ? 16 : -16), y: w.pos.y + 6)]
        } else if !atJob {
            captain.onJob = true
            captain.route = [spot]
        } else if wander {
            captain.onJob = false
            if state == .working {
                patrolIndex = (patrolIndex + 1) % theme.patrol.count
                captain.route = [theme.patrol[patrolIndex]]
            } else if let p = theme.idleSpots.randomElement() {
                captain.route = [p]
            }
        } else {
            captain.onJob = true
            captain.pauseUntil = t + Double.random(in: 8...16)
        }
    }

    private func scheduleChat(t: Double) {
        guard t > nextChatAt else { return }
        let free = subs.indices.filter { subs[$0].phase == .working && subs[$0].mood == .none && !subs[$0].dragged }
        guard free.count >= 2 else { return }
        nextChatAt = t + Double.random(in: 25...45)
        let a = free[0], b = free[1]
        subs[a].phase = .chatting
        subs[a].chatPartner = subs[b].id
        subs[a].pauseUntil = 0
        let bp = subs[b].pos
        subs[a].route = [CGPoint(x: bp.x + (subs[a].pos.x < bp.x ? -16 : 16), y: bp.y)]
    }

    private func advance(_ a: inout Actor, speed: CGFloat, dt: Double, t: Double) {
        if a.dragged || t < a.spawnAt { return }
        guard let target = a.route.first else { return }
        let dx = target.x - a.pos.x, dy = target.y - a.pos.y
        let d = hypot(dx, dy)
        let step = speed * CGFloat(dt) * (a.ctx > 0.9 ? 0.8 : 1) * (a.mood == .panic ? 1.6 : (a.mood == .tired ? 0.7 : (a.mood == .sick ? 0.45 : 1)))
        if d <= step {
            a.pos = target
            a.route.removeFirst()
            if a.route.isEmpty { arrived(&a, t: t) }
        } else {
            a.pos.x += dx / d * step
            a.pos.y += dy / d * step
            a.walked += step
            a.heading = atan2(dx, dy)
        }
    }

    private func arrived(_ a: inout Actor, t: Double) {
        a.heading = 0
        if a.isCaptain {
            a.pauseUntil = max(a.pauseUntil, t + Double.random(in: 2.5...5))
            if a.onJob, a.pending == nil, a.chatPartner == nil { a.pauseUntil = t + Double.random(in: 8...16) }
            if let pid = a.pending {
                a.pending = nil
                if theme == .football {
                    a.mood = .card
                    a.moodUntil = t + 3.2
                    a.carry = .card
                    a.say = "🟥 Red card!"
                    a.sayUntil = t + 3
                    mutate(pid) {
                        $0.phase = .onBreak
                        $0.carded = true
                        $0.route = [theme.coffee]
                        $0.pauseUntil = 0
                        $0.mood = .sad
                        $0.moodUntil = t + 9
                        $0.say = "😡 Unfair!"
                        $0.sayUntil = t + 3
                    }
                } else {
                    a.mood = .sip
                    a.moodUntil = t + 3
                    a.carry = .cup
                    a.say = "There, there… 💊"
                    a.sayUntil = t + 3
                    mutate(pid) { $0.mood = .none; $0.moodUntil = t; $0.say = "Phew! 🙂"; $0.sayUntil = t + 3 }
                }
                if let p = subs.first(where: { $0.id == pid }) { a.heading = atan2(p.pos.x - a.pos.x, p.pos.y - a.pos.y) }
                return
            }
            if let pid = a.chatPartner {
                a.chatPartner = nil
                a.say = "Status report?"
                a.sayUntil = t + 2.4
                mutate(pid) { $0.say = "On it, boss!"; $0.sayUntil = t + 3 }
                if let p = subs.first(where: { $0.id == pid }) {
                    a.heading = atan2(p.pos.x - a.pos.x, p.pos.y - a.pos.y)
                }
            } else if dist(a.pos, theme.coffee) < 14 {
                a.mood = .sip
                a.moodUntil = t + 4
                a.carry = .cup
                a.pauseUntil = t + Double.random(in: 5...9)
            }
            return
        }
        switch a.phase {
        case .arriving:
            a.phase = .working
            a.stationSince = t
        case .onBreak where a.pauseUntil == 0 && a.carded:
            a.carded = false
            a.mood = .sad
            a.moodUntil = t + 5
            a.say = "Next time…"
            a.sayUntil = t + 3
            a.pauseUntil = t + 5
        case .onBreak where a.pauseUntil == 0:
            a.mood = .sip
            a.moodUntil = t + 4
            a.carry = .cup
            a.pauseUntil = t + 4
        case .chatting where a.pauseUntil == 0:
            a.pauseUntil = t + 4
            a.mood = .chat
            a.moodUntil = t + 4
            if let pid = a.chatPartner {
                a.say = ["Got a sec?", "Seen the logs?", "Quick question…"].randomElement()
                a.sayUntil = t + 2
                mutate(pid) {
                    $0.mood = .chat
                    $0.moodUntil = t + 4
                    $0.say = ["Sure!", "Yeah, nuts.", "Go on…"].randomElement()
                    $0.sayUntil = t + 4
                }
            }
        default:
            break
        }
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Sub-agent sync

    private func syncSubs(_ current: [SubAgent], t: Double) {
        let ids = Set(current.map(\.id))
        var finishedNow = false
        defer { if finishedNow, !subs.contains(where: { ids.contains($0.id) }) { emit(.celebration) } }
        for i in subs.indices where !ids.contains(subs[i].id) && subs[i].phase != .leaving && subs[i].phase != .finishing {
            subs[i].phase = .finishing
            subs[i].mood = .celebrate
            subs[i].moodUntil = t + 2.4
            subs[i].say = theme.celebrateLine
            subs[i].sayUntil = t + 2.4
            subs[i].route = []
            subs[i].carry = theme == .kitchen ? .plate : (theme == .prison ? .papers : (theme == .football ? .ball : nil))
            events.append(.finished(subs[i].name))
            emit(.success(subs[i].pos))
            finishedNow = true
        }
        for s in current {
            if let i = subs.firstIndex(where: { $0.id == s.id }) {
                subs[i].tool = s.tool
                subs[i].busy = s.busy
                subs[i].actions = s.actions
                subs[i].model = s.model
                subs[i].ageSec = Date().timeIntervalSince(s.startedAt)
                applyMetrics(&subs[i], ctx: s.contextFraction, cost: s.costCredits, approval: s.waitingApproval, success: s.successRate, calls: s.toolCalls, t: t)
            } else {
                addSub(s, t: t)
            }
        }
    }

    private func addSub(_ s: SubAgent, t: Double) {
        let kind = Theme.toolKind(s.tool)
        let slot = pickSlot()
        let jobSlot = Jobs.pickSlot(id: s.id, taken: takenSlots(excluding: s.id), theme: theme)
        let target = s.busy ? stationTarget(kind, excluding: s.id) : jobSlots[jobSlot].pos
        let already = Date().timeIntervalSince(s.startedAt) > 6
        var a = Actor(id: s.id, name: s.displayName.replacingOccurrences(of: " Agent", with: ""), model: s.model,
                      startedAt: s.startedAt, isCaptain: false, variant: Sprite3D.stableHash(s.name),
                      pos: already ? target : theme.spawn(slot: slot))
        a.station = kind
        a.kind = kind
        a.jobSlot = jobSlot
        a.onJob = !s.busy
        a.slot = slot
        a.tool = s.tool
        a.busy = s.busy
        a.actions = s.actions
        a.stationSince = t
        a.nextTalk = t + Double.random(in: 4...12)
        a.breakAt = t + Double.random(in: 80...140)
        a.lastSwitch = t
        a.ageSec = Date().timeIntervalSince(s.startedAt)
        if already {
            a.phase = .working
        } else {
            a.phase = .arriving
            a.route = theme.waypoints(slot: slot) + [target]
            a.spawnAt = max(t, lastSpawnAt + 1.1)
            lastSpawnAt = a.spawnAt
            events.append(.spawned)
            spawnQueue.append(a.id)
        }
        applyMetrics(&a, ctx: s.contextFraction, cost: s.costCredits, approval: s.waitingApproval, success: s.successRate, calls: s.toolCalls, t: t)
        subs.append(a)
    }

    private func applyMetrics(_ a: inout Actor, ctx: Double, cost: Double, approval: Bool, success: Double, calls: Int, t: Double) {
        if a.costSeen, a.ctx - ctx > 0.3 {
            a.compactEvents += 1
            a.say = "🗜️ Compacting…"
            a.sayUntil = t + 2.6
        }
        if a.costSeen, cost > a.cost + 0.004 {
            a.costEvents += 1
            a.costDelta = cost - a.cost
        }
        a.costSeen = true
        a.ctx = ctx
        a.cost = cost
        a.approval = approval
        a.success = success
        a.calls = calls
    }

    private func pickSlot() -> Int {
        let counts = (0..<Theme.cellSlots).map { i in subs.filter { $0.slot == i && $0.phase != .leaving }.count }
        return counts.indices.min { counts[$0] < counts[$1] } ?? 0
    }

    func stationTarget(_ i: Int, excluding id: String) -> CGPoint {
        let n = subs.filter { $0.id != id && $0.station == i && ![.leaving, .finishing].contains($0.phase) }.count
        let base = theme.stations[i % theme.stations.count].pos
        let col = n % 3, row = n / 3
        return CGPoint(x: base.x + CGFloat(col) * 14, y: base.y + CGFloat(col % 2) * 4 + CGFloat(row) * 12)
    }
}

/// Keeps one RoomSim per session and advances them on every tick.
final class World {
    private var rooms: [String: RoomSim] = [:]
    private var lastT: Double?

    func sim(for id: String) -> RoomSim? { rooms[id] }
    var allSims: [RoomSim] { Array(rooms.values) }

    func step(sessions: [SessionInfo], theme: Theme, t: Double) {
        let dt = min(max(t - (lastT ?? t), 0), 0.2)
        lastT = t
        let ids = Set(sessions.map(\.id))
        rooms = rooms.filter { ids.contains($0.key) || $0.key == "__empty" }
        for s in sessions {
            let sim = rooms[s.id] ?? RoomSim(theme: theme)
            rooms[s.id] = sim
            sim.update(session: s, theme: theme, t: t, dt: dt)
        }
        if sessions.isEmpty {
            let sim = rooms["__empty"] ?? RoomSim(theme: theme)
            rooms["__empty"] = sim
            sim.update(session: nil, theme: theme, t: t, dt: dt)
        }
    }

    func emptySim() -> RoomSim? { rooms["__empty"] }
}

enum Sprite3D {
    static func stableHash(_ s: String) -> Int {
        s.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }
}
