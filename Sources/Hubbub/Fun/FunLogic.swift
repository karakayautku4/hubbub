import Foundation

// Pure, deterministic logic behind race mode and surprise guests (no SceneKit, so `--selftest-fun` can cover it).

// MARK: Race maths

enum RaceMath {
    /// Track fractions per second. Idle agents amble, busy ones sprint with their real tool-call and token rates.
    static func speed(callsPerMin: Double, tokensPerSec: Double, busy: Bool) -> Double {
        guard busy else { return 0.012 }
        let calls = min(0.06, max(0, callsPerMin) * 0.004)
        let tokens = min(0.03, max(0, tokensPerSec) / 1500)
        return 0.03 + calls + tokens
    }

    static let stumbleSeconds = 1.4
    static let stumbleSetback = 0.025
    static let maxRacers = 5
    static let obstacleSpots: [Double] = [0.24, 0.5, 0.76]

    /// Stable ±3 % personality so equally busy agents do not finish in a dead heat.
    static func jitter(_ id: String) -> Double {
        1 + Double(id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 7 - 3) * 0.01
    }
}

/// Smoothed activity rates from monotonically growing counters (20 s time constant).
struct RaceRate {
    private(set) var callsPerMin = 0.0
    private(set) var tokensPerSec = 0.0
    private var lastCalls: Int?
    private var lastTokens = 0
    private var lastFailures = 0
    private var lastT = 0.0

    /// Returns true when new failures appeared since the previous sample.
    @discardableResult
    mutating func feed(calls: Int, tokens: Int, failures: Int, t: Double) -> Bool {
        guard let lc = lastCalls else {
            lastCalls = calls; lastTokens = tokens; lastFailures = failures; lastT = t
            return false
        }
        let dt = t - lastT
        guard dt >= 0.5 else { return false }
        let a = 1 - exp(-dt / 20)
        callsPerMin += (Double(max(0, calls - lc)) / dt * 60 - callsPerMin) * a
        tokensPerSec += (Double(max(0, tokens - lastTokens)) / dt - tokensPerSec) * a
        let failed = failures > lastFailures
        lastCalls = calls; lastTokens = tokens; lastFailures = failures; lastT = t
        return failed
    }
}

struct RaceRacer: Equatable {
    var id: String
    var name: String
    var progress = 0.0
    var speed = 0.0
    var stumbleUntil = 0.0
    var stumbles = 0
    var finishedAt: Double?
}

struct RaceState {
    var racers: [RaceRacer]
    var clock = 0.0
    var winner: String?
    static let timeLimit = 45.0

    init(_ racers: [RaceRacer]) { self.racers = racers }

    func isStumbling(_ i: Int) -> Bool { clock < racers[i].stumbleUntil }

    mutating func stumble(_ id: String) {
        guard let i = racers.firstIndex(where: { $0.id == id }), racers[i].finishedAt == nil, !isStumbling(i) else { return }
        racers[i].stumbleUntil = clock + RaceMath.stumbleSeconds
        racers[i].stumbles += 1
        racers[i].progress = max(0, racers[i].progress - RaceMath.stumbleSetback)
    }

    mutating func advance(_ dt: Double) {
        clock += dt
        for i in racers.indices where racers[i].finishedAt == nil {
            if clock >= racers[i].stumbleUntil { racers[i].progress += racers[i].speed * dt }
            if racers[i].progress >= 1 {
                racers[i].progress = 1
                racers[i].finishedAt = clock
                if winner == nil { winner = racers[i].id }
            }
        }
        if winner == nil, clock >= Self.timeLimit, let lead = racers.max(by: { $0.progress < $1.progress }) { winner = lead.id }
    }

    var isOver: Bool { winner != nil }

    /// Finishers by arrival time, then everyone else by distance covered.
    var ranking: [RaceRacer] {
        racers.sorted {
            switch ($0.finishedAt, $1.finishedAt) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.progress > $1.progress
            }
        }
    }
}

// MARK: Announcer

enum RaceText {
    private struct Lines { let start: String; let stumble: [String]; let win: [String] }

    private static func lines(_ theme: Theme) -> Lines {
        if let l = ThemeExtensions.active?.raceLines(theme) { return Lines(start: l.start, stumble: l.stumble, win: l.win) }
        return switch theme {
        case .space: Lines(start: "T-minus three, two, one… dash!",
                           stumble: ["{n} tripped over a very small crater.", "{n} forgot gravity is optional."],
                           win: ["{n} crosses the line before the oxygen alarm!", "{n} wins, powered by pure moon dust."])
        case .kitchen: Lines(start: "Chefs, on your marks. Mind the rolling pins!",
                             stumble: ["{n} slipped on a rogue pea.", "{n} was out-rolled by a rolling pin."],
                             win: ["{n} wins, and the soufflé did not even fall!", "{n} is the main course today."])
        case .prison: Lines(start: "Yard dash! Nobody is escaping, it is a race.",
                            stumble: ["{n} tripped over the paperwork.", "{n} ran into the world's politest hurdle."],
                            win: ["{n} takes gold. Parole not included.", "{n} wins the fastest sentence ever served."])
        case .football: Lines(start: "Sprint challenge! Referees, please keep your whistles dry.",
                              stumble: ["{n} dives. The crowd is not convinced.", "{n} takes a very dramatic tumble."],
                              win: ["{n} breaks the tape. What a goal-less finish!", "{n} wins. The trophy is a ball, obviously."])
        case .farm: Lines(start: "Sheep sprint! Wool you win? Ready, set, baa!",
                          stumble: ["{n} got tangled in its own wool.", "{n} stopped to eye a suspicious clover."],
                          win: ["{n} wins by a fleece!", "{n} is the woolliest winner of the year."])
        case .impostor: Lines(start: "Corridor dash! Nobody looks suspicious. Go!",
                              stumble: ["{n} tripped on a vent. Very sus.", "{n} blamed the wiring."],
                              win: ["{n} wins. Crew huddle adjourned.", "{n} crosses first. Nobody saw anything."])
        case .wizard: Lines(start: "Broom hurdles! Brooms are optional, spells are not.",
                            stumble: ["{n} hexed their own shoelaces.", "{n} tripped over a stack of overdue books."],
                            win: ["{n} wins by a whisker and a wand!", "{n} sparkles across the line."])
        case .galactic: Lines(start: "Hyperlane heat! Engage the sprint thrusters!",
                              stumble: ["{n} clipped an energy gate.", "{n} lost a bolt but kept the attitude."],
                              win: ["{n} wins at near-light speed!", "{n} beats the clock and the nav computer."])
        case .fellowship: Lines(start: "The Great Meadow Run! A hot pie is the prize.",
                                stumble: ["{n} stubbed a toe on a cairn.", "{n} stopped to smell a very nice flower."],
                                win: ["{n} wins. A sit-down is now mandatory.", "{n} arrives first, with snacks."])
        default: Lines(start: "Ready, set, go!", stumble: ["{n} stumbles!"], win: ["{n} wins!"])
        }
    }

    static func start(_ theme: Theme) -> String { lines(theme).start }
    static func stumble(_ theme: Theme, name: String, roll: Double) -> String { pick(lines(theme).stumble, roll).replacingOccurrences(of: "{n}", with: name) }
    static func win(_ theme: Theme, name: String, roll: Double) -> String { pick(lines(theme).win, roll).replacingOccurrences(of: "{n}", with: name) }

    private static func pick(_ a: [String], _ roll: Double) -> String { a[min(a.count - 1, Int(max(0, min(0.999, roll)) * Double(a.count)))] }

    static func title(_ theme: Theme) -> String {
        if let t = ThemeExtensions.active?.raceTitle(theme) { return t }
        return switch theme {
        case .space: "MOON DASH"
        case .kitchen: "KITCHEN SPRINT"
        case .prison: "YARD DASH"
        case .football: "SPRINT 100"
        case .farm: "SHEEP SPRINT"
        case .impostor: "CORRIDOR DASH"
        case .wizard: "BROOM HURDLES"
        case .galactic: "HYPERLANE HEAT"
        case .fellowship: "MEADOW RUN"
        default: "THE BIG RACE"
        }
    }
}

// MARK: Surprise guests

enum GuestKind: String, CaseIterable {
    case merchant, ufo, ghost, bard, alien, partyPal

    var title: String {
        switch self {
        case .merchant: "Travelling Merchant"
        case .ufo: "Curious Saucer"
        case .ghost: "Friendly Ghost"
        case .bard: "Wandering Bard"
        case .alien: "Alien Tourist"
        case .partyPal: "Party Pal"
        }
    }

    var arrival: String {
        switch self {
        case .merchant: "Fresh wares! Slightly used, mostly legal!"
        case .ufo: "bzzzzt… just passing through."
        case .ghost: "Boo! …sorry, force of habit."
        case .bard: "A ballad for the busy bots!"
        case .alien: "Take me to your build server!"
        case .partyPal: "Did somebody say party?"
        }
    }

    var clickLines: [String] {
        switch self {
        case .merchant: ["Rare goods! One lightly haunted teapot?", "No refunds. Not even for the cursed ones.", "I accept hugs, nods and tokens."]
        case .ufo: ["We borrow chairs. For science.", "Your chairs are fascinating.", "Do not worry. We will return it. Probably."]
        case .ghost: ["Woooo-hoo! I love a deadline.", "I would haunt your logs, but they're already scary.", "Can I help review the PR? I'm see-through."]
        case .bard: ["♪ Oh, the tokens flow like wine… ♪", "♪ Merge, merge, never fail… ♪", "That one is called \"Ode to a Green Build\"."]
        case .alien: ["Smile! This is for the group chat back home.", "Your planet has such nice terminals!", "Is this where the magic compiles?"]
        case .partyPal: ["Confetti is a lifestyle!", "Every green build deserves a party hat.", "Pop! Pop! Hooray!"]
        }
    }

    var leaveLine: String {
        switch self {
        case .merchant: "Back to the road. Buy something next time!"
        case .ufo: "We have your chair. Thanks!"
        case .ghost: "Gotta glide. Spooky regards!"
        case .bard: "Encore tomorrow!"
        case .alien: "Five stars. Would orbit again."
        case .partyPal: "Party's moving on!"
        }
    }
}

enum GuestOccasion: Equatable {
    case random
    case milestone(Int)
    case special(String)
}

enum GuestPlan {
    static let minGap: TimeInterval = 45
    static let randomGap: TimeInterval = 600
    static let randomChance = 0.012
    static let milestoneEvery = 10
    static let checkInterval = 30.0

    /// Named occasion for the given day, if any.
    static func specialDay(_ date: Date, calendar: Calendar) -> String? {
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        guard let m = c.month, let d = c.day else { return nil }
        if d == 13, c.weekday == 6 { return "friday13" }
        switch (m, d) {
        case (1, 1), (12, 31): return "newyear"
        case (10, 31): return "halloween"
        case (4, 1): return "aprilfools"
        case (2, 29): return "leapday"
        default: return nil
        }
    }

    static func dayKey(_ name: String, _ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(name)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// `roll` is a uniform 0..<1 sample; everything else is state, so the decision is deterministic.
    static func decide(now: Date, calendar: Calendar, lastGuestAt: Date?, lastSpecialKey: String?,
                       pendingMilestone: Int?, roll: Double) -> GuestOccasion? {
        let since = lastGuestAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard since >= minGap else { return nil }
        if let s = specialDay(now, calendar: calendar), dayKey(s, now, calendar: calendar) != lastSpecialKey { return .special(s) }
        if let m = pendingMilestone { return .milestone(m) }
        if since >= randomGap, roll < randomChance { return .random }
        return nil
    }

    static func pool(_ theme: Theme) -> [GuestKind] {
        if let p = ThemeExtensions.active?.guestPool(theme) { return p }
        return switch theme {
        case .space, .galactic, .impostor: [.alien, .ufo, .merchant, .bard, .alien, .ghost]
        case .kitchen: [.merchant, .bard, .partyPal, .ghost, .ufo, .merchant]
        case .prison: [.merchant, .ghost, .bard, .ufo, .partyPal, .ghost]
        case .football: [.bard, .partyPal, .merchant, .alien, .ghost, .partyPal]
        case .farm: [.ufo, .merchant, .bard, .ufo, .ghost, .partyPal]
        case .wizard, .fellowship: [.bard, .merchant, .ghost, .bard, .alien, .partyPal]
        default: [.merchant, .bard, .ghost, .ufo, .alien, .partyPal]
        }
    }

    static func kind(for occasion: GuestOccasion, theme: Theme, roll: Double) -> GuestKind {
        if case .special(let s) = occasion {
            switch s {
            case "friday13", "halloween": return .ghost
            case "newyear": return .partyPal
            case "aprilfools": return .alien
            default: return .merchant
            }
        }
        let p = pool(theme)
        return p[min(p.count - 1, Int(max(0, min(0.999, roll)) * Double(p.count)))]
    }

    /// Theme-flavoured aside appended to a click reaction now and then.
    static func quip(_ theme: Theme) -> String {
        if let q = ThemeExtensions.active?.guestQuip(theme) { return q }
        return switch theme {
        case .space: "Nice station. Where do I park?"
        case .kitchen: "Is the soup supposed to glow?"
        case .prison: "Lovely bars. Very secure."
        case .football: "Who is winning? Everybody?"
        case .farm: "Excellent sheep. Very fluffy."
        case .impostor: "Everybody here seems totally normal."
        case .wizard: "Mind if I borrow a spellbook?"
        case .galactic: "Your fleet could use more cup holders."
        case .fellowship: "Any chance of a second helping?"
        default: "What a lovely place to work."
        }
    }

    static func occasionLine(_ occasion: GuestOccasion, kind: GuestKind) -> String {
        switch occasion {
        case .special("friday13"): return "Friday the 13th! Do not worry, I am the only unlucky one."
        case .special("newyear"): return "Happy New Year, agents! 🎉"
        case .special("halloween"): return "Trick or tokens?"
        case .special("aprilfools"): return "Nothing is real today. Even the chairs."
        case .special("leapday"): return "A rare day! Rare goods for a rare day."
        case .milestone(let n): return "Wow, \(n) finished sessions! Time to celebrate."
        default: return kind.arrival
        }
    }
}
