import SwiftUI

struct Station {
    let pos: CGPoint
    let emoji: String
    let label: String
}

enum Theme: String, CaseIterable, Identifiable {
    case space, kitchen, prison, football, farm
    case impostor, wizard, galactic, fellowship
    var id: String { rawValue }

    static let defaultTheme: Theme = .space

    /// Maps a persisted raw value to a theme, falling back to the default for unknown or unavailable themes.
    static func resolve(_ raw: String) -> Theme { Theme(rawValue: raw) ?? defaultTheme }

    static let worldSize = CGSize(width: 320, height: 180)
    static let floorY: CGFloat = 96

    var title: String {
        switch self {
        case .space: "Space Station"
        case .kitchen: "Restaurant Kitchen"
        case .prison: "Prison"
        case .football: "Football Match"
        case .farm: "Sheep Farm"
        case .impostor: "Sneaky Ship"
        case .wizard: "Spell Academy"
        case .galactic: "Galactic Fleet"
        case .fellowship: "Hillside Quest"
        }
    }
    var icon: String {
        switch self {
            case .space: "🚀"
            case .kitchen: "🍳"
            case .prison: "⛓️"
            case .football: "⚽"
            case .farm: "🐑"
            case .impostor: "🛸"
            case .wizard: "🪄"
            case .galactic: "🌌"
            case .fellowship: "🗡️"
        }
    }
    var blurb: String {
        switch self {
        case .space: "Each session is a station module. The commander supervises a crew repairing and operating the station."
        case .kitchen: "Each session is a kitchen. The head chef oversees cooks chopping, mixing and cooking."
        case .prison: "Each session is a prison. The warden hands out jobs; inmates leave their cells to do community service."
        case .football: "Each session is a match. The referee runs the game while your team's players train; a failed task earns a red card."
        case .farm: "Each session is a farm. The farmer looks after a flock of sheep; a failed task makes a sheep sick (and green!) until it gets medicine."
        case .impostor: "Each session is a spaceship. The captain keeps a bean-shaped crew busy with tasks; a failed task means someone is acting very, very sus."
        case .wizard: "Each session is a castle school. The headwizard teaches apprentices spells and potions; a failed task makes a spell backfire."
        case .galactic: "Each session is a starship. The admiral leads a squadron of cadets and helper bots; a failed task sets off the red alert."
        case .fellowship: "Each session is a quest. The wise guide leads a band of adventurers across the realm; a failed task means chaos: a giant eagle, burnt stew or a runaway lucky charm."
        }
    }
    var captainRole: String {
        if let v = ov?.characters?.captainTitle { return v }
        return switch self {
            case .space: "Commander"
            case .kitchen: "Head Chef"
            case .prison: "Warden"
            case .football: "Referee"
            case .farm: "Farmer"
            case .impostor: "Captain"
            case .wizard: "Headwizard"
            case .galactic: "Admiral"
            case .fellowship: "Wise Guide"
        }
    }
    var subRole: String {
        if let v = ov?.characters?.subagentRole { return v }
        return switch self {
            case .space: "crew member"
            case .kitchen: "cook"
            case .prison: "inmate"
            case .football: "player"
            case .farm: "sheep"
            case .impostor: "shipmate"
            case .wizard: "apprentice"
            case .galactic: "cadet"
            case .fellowship: "adventurer"
        }
    }
    var quotaLabel: String {
        if let v = ov?.labels?.quota { return v }
        return switch self {
            case .space: "Fuel / Oxygen"
            case .kitchen: "Gas Tank"
            case .prison: "Prison Budget"
            case .football: "Stamina"
            case .farm: "Hay Supply"
            case .impostor: "Reactor Fuel"
            case .wizard: "Mana Potion"
            case .galactic: "Hyperdrive Fuel"
            case .fellowship: "Trail Rations"
        }
    }
    var roomNoun: String {
        if let v = ov?.labels?.roomNoun { return v }
        return switch self {
            case .space: "Module"
            case .kitchen: "Kitchen"
            case .prison: "Prison"
            case .football: "Pitch"
            case .farm: "Farm"
            case .impostor: "Ship"
            case .wizard: "Castle"
            case .galactic: "Starship"
            case .fellowship: "Quest"
        }
    }
    var emptyText: String {
        if let v = ov?.labels?.empty { return v }
        return switch self {
        case .space: "The station is quiet…"
        case .kitchen: "The kitchen is closed…"
        case .prison: "Lights out, no sessions…"
        case .football: "The stadium is empty…"
        case .farm: "The flock is asleep…"
        case .impostor: "The ship is suspiciously quiet…"
        case .wizard: "The castle is fast asleep…"
        case .galactic: "The fleet is on standby…"
        case .fellowship: "The road is empty…"
        }
    }
    var idleText: String {
        if let v = ov?.labels?.idle { return v }
        return switch self {
        case .space: "💭 Awaiting orders"
        case .kitchen: "💭 Waiting for orders"
        case .prison: "💭 Waiting for new inmates"
        case .football: "💭 Waiting for kick-off"
        case .farm: "💭 Waiting for the flock"
        case .impostor: "💭 Waiting in the cafeteria"
        case .wizard: "💭 Waiting for the bell"
        case .galactic: "💭 Awaiting fleet orders"
        case .fellowship: "💭 Resting at the inn"
        }
    }
    var thinkingText: String {
        if let v = ov?.labels?.thinking { return v }
        return switch self {
        case .space: "🧠 Plotting a course…"
        case .kitchen: "🧠 Planning the menu…"
        case .prison: "🧠 Reviewing case files…"
        case .football: "🧠 Drawing up tactics…"
        case .farm: "🧠 Counting sheep…"
        case .impostor: "🧠 Figuring out who is sus…"
        case .wizard: "🧠 Consulting the spellbook…"
        case .galactic: "🧠 Calculating the jump…"
        case .fellowship: "🧠 Studying the map…"
        }
    }
    var packet: Color {
        switch self {
        case .space: Color(red: 0.4, green: 0.9, blue: 1.0)
        case .kitchen: .white
        case .prison: Color(red: 1.0, green: 0.9, blue: 0.4)
        case .football: .white
        case .farm: Color(red: 1.0, green: 0.95, blue: 0.6)
        case .impostor: Color(red: 0.45, green: 0.95, blue: 1.0)
        case .wizard: Color(red: 0.85, green: 0.7, blue: 1.0)
        case .galactic: Color(red: 0.5, green: 1.0, blue: 0.55)
        case .fellowship: Color(red: 1.0, green: 0.85, blue: 0.45)
        }
    }
    var previewColors: [Color] {
        switch self {
        case .space: [Color(red: 0.05, green: 0.05, blue: 0.2), Color(red: 0.6, green: 0.3, blue: 0.8)]
        case .kitchen: [Color(red: 0.99, green: 0.93, blue: 0.80), Color(red: 0.85, green: 0.5, blue: 0.3)]
        case .prison: [Color(red: 0.35, green: 0.36, blue: 0.4), Color(red: 0.96, green: 0.52, blue: 0.1)]
        case .football: [Color(red: 0.08, green: 0.4, blue: 0.15), Color(red: 0.95, green: 0.95, blue: 0.95)]
        case .farm: [Color(red: 0.55, green: 0.8, blue: 0.95), Color(red: 0.35, green: 0.65, blue: 0.25)]
        case .impostor: [Color(red: 0.1, green: 0.12, blue: 0.2), Color(red: 0.85, green: 0.15, blue: 0.2)]
        case .wizard: [Color(red: 0.16, green: 0.1, blue: 0.3), Color(red: 0.95, green: 0.75, blue: 0.2)]
        case .galactic: [Color(red: 0.02, green: 0.03, blue: 0.08), Color(red: 0.3, green: 0.85, blue: 0.4)]
        case .fellowship: [Color(red: 0.25, green: 0.4, blue: 0.2), Color(red: 0.9, green: 0.75, blue: 0.4)]
        }
    }
    var labelBackdrop: Color {
        self == .kitchen ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }
    var textColor: Color {
        self == .kitchen ? Color(red: 0.25, green: 0.14, blue: 0.08) : .white
    }

    // MARK: World layout (logical coordinates: world x = (lx-160)/10, world z = (ly-96)/10)

    /// Station index matches the tool kind: 0 search/read, 1 write, 2 run, 3 everything else.
    var stations: [Station] {
        let base = builtInStations
        guard let defs = ov?.stations else { return base }
        return base.enumerated().map { i, st in
            let d = defs.first { ($0.kind ?? -1) == i } ?? (defs.indices.contains(i) && defs[i].kind == nil ? defs[i] : nil)
            return Station(pos: st.pos, emoji: d?.emoji ?? st.emoji, label: d?.label ?? st.label)
        }
    }

    private var builtInStations: [Station] {
        switch self {
        case .space:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "📡", label: "Scanning sector"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "🔧", label: "Hull repair"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "⚙️", label: "Reactor tuning"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "📻", label: "Ground comms")]
        case .kitchen:
            return [Station(pos: CGPoint(x: 66, y: 124), emoji: "🧺", label: "Fetching ingredients"),
                    Station(pos: CGPoint(x: 150, y: 152), emoji: "🔪", label: "Chopping"),
                    Station(pos: CGPoint(x: 250, y: 124), emoji: "🔥", label: "Cooking"),
                    Station(pos: CGPoint(x: 214, y: 156), emoji: "🧼", label: "Plating & dishes")]
        case .prison:
            return [Station(pos: CGPoint(x: 240, y: 128), emoji: "🌱", label: "Gardening"),
                    Station(pos: CGPoint(x: 292, y: 112), emoji: "🖌️", label: "Painting the wall"),
                    Station(pos: CGPoint(x: 206, y: 154), emoji: "🧹", label: "Sweeping the road"),
                    Station(pos: CGPoint(x: 268, y: 160), emoji: "🗑️", label: "Litter pickup")]
        case .football:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "⚽", label: "Passing drill"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "🥅", label: "Shooting practice"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "🏃", label: "Sprint training"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "📋", label: "Tactics board")]
        case .farm:
            return [Station(pos: CGPoint(x: 60, y: 126), emoji: "🌾", label: "Grazing"),
                    Station(pos: CGPoint(x: 128, y: 154), emoji: "✂️", label: "Wool spa"),
                    Station(pos: CGPoint(x: 206, y: 126), emoji: "💧", label: "Water trough"),
                    Station(pos: CGPoint(x: 262, y: 154), emoji: "🌻", label: "Sunflower patch")]
        case .impostor:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "📥", label: "Downloading data"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "🔌", label: "Fixing the wires"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "⛽", label: "Fueling the engines"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "📣", label: "Crew huddle")]
        case .wizard:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "📚", label: "Spellbook library"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "🪄", label: "Wand workshop"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "🧪", label: "Potions class"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "🦉", label: "Owl post")]
        case .galactic:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "🔭", label: "Scanning the sector"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "🤖", label: "Bot workshop"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "🚀", label: "Hyperdrive tuning"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "📡", label: "Holo-comms")]
        case .fellowship:
            return [Station(pos: CGPoint(x: 60, y: 124), emoji: "🗺️", label: "Reading the map"),
                    Station(pos: CGPoint(x: 128, y: 152), emoji: "⚒️", label: "Blacksmith forge"),
                    Station(pos: CGPoint(x: 206, y: 124), emoji: "🔥", label: "Campfire stew"),
                    Station(pos: CGPoint(x: 268, y: 152), emoji: "🚩", label: "Signpost & beacon")]
        }
    }

    static func toolKind(_ tool: String?) -> Int {
        guard let t = tool?.lowercased() else { return 0 }
        if ["grep", "glob", "view", "search", "read", "list", "find"].contains(where: t.contains) { return 0 }
        if ["edit", "create", "write", "patch", "apply"].contains(where: t.contains) { return 1 }
        if ["bash", "shell", "powershell", "run", "test", "exec"].contains(where: t.contains) { return 2 }
        return 3
    }

    var post: CGPoint { CGPoint(x: 160, y: 112) }

    var patrol: [CGPoint] {
        switch self {
        case .prison:
            return [CGPoint(x: 160, y: 112), CGPoint(x: 150, y: 150), CGPoint(x: 232, y: 142), CGPoint(x: 262, y: 128), CGPoint(x: 200, y: 168)]
        default:
            return [CGPoint(x: 160, y: 112), CGPoint(x: 100, y: 138), CGPoint(x: 168, y: 138), CGPoint(x: 236, y: 140), CGPoint(x: 160, y: 166)]
        }
    }

    /// Where the coffee machine / water cooler is; idle agents drift here.
    var coffee: CGPoint {
        switch self {
        case .space: CGPoint(x: 100, y: 112)
        case .kitchen: CGPoint(x: 100, y: 112)
        case .prison: CGPoint(x: 176, y: 112)
        case .football: CGPoint(x: 104, y: 112)
        case .farm: CGPoint(x: 110, y: 114)
        case .impostor, .wizard, .galactic, .fellowship: CGPoint(x: 100, y: 112)
        }
    }

    var idleSpots: [CGPoint] {
        [coffee, CGPoint(x: 160, y: 150), CGPoint(x: 230, y: 118), CGPoint(x: 90, y: 150), post]
    }

    /// Where finished workers go to leave the map.
    var exit: CGPoint {
        switch self {
        case .kitchen: CGPoint(x: 296, y: 126)
        case .prison: CGPoint(x: 314, y: 152)
        case .farm: CGPoint(x: 296, y: 122)
        default: CGPoint(x: 10, y: 150)
        }
    }

    static let cellSlots = 3

    func spawn(slot: Int) -> CGPoint {
        switch self {
        case .prison: CGPoint(x: 22 + CGFloat(slot % Theme.cellSlots) * 40, y: 120)
        case .farm: CGPoint(x: 296, y: 116 + CGFloat(slot % 3) * 12)
        default: CGPoint(x: 10, y: 134 + CGFloat(slot % 3) * 13)
        }
    }

    /// Points a worker passes through on the way from `spawn` to a station.
    func waypoints(slot: Int) -> [CGPoint] {
        switch self {
        case .prison:
            let s = spawn(slot: slot)
            return [CGPoint(x: s.x, y: 142), CGPoint(x: 205, y: 142)]
        default: return []
        }
    }

    var celebrateLine: String {
        if let v = ov?.phrases?.success?.randomElement() { return v }
        return switch self {
        case .space: "Mission complete! 🚀"
        case .kitchen: "Order up! 🛎️"
        case .prison: "Free at last! 🎉"
        case .football: "GOAL! ⚽️🎉"
        case .farm: "Baa-rilliant! 🐑"
        case .impostor: "All tasks done! ✅"
        case .wizard: "Ten points! ✨"
        case .galactic: "Mission accomplished! 🌠"
        case .fellowship: "Quest complete! 🏔️"
        }
    }
    var panicLine: String {
        if let v = ov?.phrases?.failure?.randomElement() { return v }
        return switch self {
        case .space: "Hull breach! 💥"
        case .kitchen: "Fire! 🔥"
        case .prison: "Riot! 🚨"
        case .football: "Foul! 🟥"
        case .farm: "Baa?! 😨"
        case .impostor: "That was sus! 🚨"
        case .wizard: "Spell backfired! 💫"
        case .galactic: "Red alert! 🚨"
        case .fellowship: "Giant eagle! 🦅"
        }
    }
    var deskLine: String {
        return "Reviewing case files…"
    }
    var coffeeLine: String {
        return "Coffee time ☕️"
    }
    var tiredLine: String {
        if let v = ov?.phrases?.idle?.randomElement() { return v }
        return switch self {
        case .prison: "Need a smoke break…"
        case .football: "Need some water…"
        case .farm: "Need a drink…"
        case .impostor: "Need a snack…"
        case .wizard: "Need a cauldron cocoa…"
        case .galactic: "Need some space juice…"
        case .fellowship: "Need a hearty snack…"
        default: "Need a coffee…"
        }
    }

    func chatter(kind: Int) -> [String] {
        if let w = ov?.phrases?.working, !w.isEmpty { return w }
        return switch self {
        case .space:
            [["Scanning the sector", "Nothing on radar", "Reading telemetry"], ["Welding the hull", "Patching a panel", "Tightening bolts"],
             ["Reactor at 98%", "Engines humming", "Running diagnostics"], ["Calling ground", "Relaying a message", "Signal is weak"]][kind]
        case .kitchen:
            [["Need more thyme", "Checking the pantry", "Fresh basil!"], ["Chop chop chop", "Julienne!", "Sharp knife"],
             ["Hot pan!", "Sizzling!", "Don't burn it"], ["Plating up", "Wiping the plate", "Dishes piling up"]][kind]
        case .prison:
            [["Watering the roses", "Planting seeds", "Nice soil"], ["Painting the wall", "Needs a 2nd coat", "Stay in the lines"],
             ["Sweeping up", "So much dust", "Clean road"], ["Picking up litter", "Who dropped this?", "Bag is full"]][kind]
        case .football:
            [["One-two!", "Nice pass", "Keep the ball moving"], ["Shoot!", "Top corner!", "What a strike"],
             ["Sprint!", "Another lap", "Feeling the burn"], ["Switch to 4-3-3", "Press high!", "Watch the offside"]][kind]
        case .farm:
            [["Baa… yum grass", "Munch munch", "Fresh clover!"], ["Baaa… so fluffy", "Spa day", "Mind the wool"],
             ["Slurp slurp", "Cool water", "Baa… refreshing"], ["Pretty flowers", "Baa! Sunshine", "Bzzz bee!"]][kind]
        case .impostor:
            [["Uploading… 42%", "Downloading data", "Where is everyone?"], ["Wires: red, blue, yellow", "Fixing the lights", "Not me, I swear"],
             ["Fuel line connected", "Engines humming", "Calibrating"], ["Who left the hatch open?", "Quiet, I'm thinking", "I was in the engine room"]][kind]
        case .wizard:
            [["Chapter 7: Levitation", "Shh, library!", "Dusty tome…"], ["Twirl and zap!", "Wand is humming", "Oops, sparks"],
             ["Bubble bubble", "Add a newt tail", "It turned purple"], ["Hoo hoo!", "Owl post for you", "Feathers everywhere"]][kind]
        case .galactic:
            [["Sector looks clear", "Strange signal…", "Reading the sensors"], ["Beep boop", "Bot needs oil", "Bolting a panel"],
             ["Hyperdrive at 99%", "Jump in 3, 2, 1", "Charging the engines"], ["Incoming hologram", "Patch me through", "Signal is fuzzy"]][kind]
        case .fellowship:
            [["Which way is north?", "The map says mountain", "Are we lost?"], ["Clang clang!", "A fine axe", "Hot iron!"],
             ["Stew is ready", "More salt?", "Smells like dinner"], ["Light the beacon!", "This way… or that?", "Signpost says \"nope\""]][kind]
        }
    }

    func action(for tool: String?) -> String? {
        guard let tool else { return nil }
        let t = tool.lowercased()
        let table: [(String, String)]
        switch self {
        case .space:
            table = [("bash", "⚙️ Firing the engines"), ("edit", "🔧 Repairing the hull"), ("create", "🛠️ Building a module"),
                     ("view", "📡 Scanning"), ("grep", "🛰️ Searching the sector"), ("glob", "🛰️ Searching the sector"),
                     ("task", "📻 Tasking the crew"), ("fetch", "🌐 Contacting ground control"),
                     ("ask_user", "💬 Awaiting orders")]
        case .kitchen:
            table = [("bash", "🔥 Cooking on the stove"), ("edit", "🔪 Chopping"), ("create", "🍰 Creating a new recipe"),
                     ("view", "👀 Tasting"), ("grep", "🧺 Hunting for ingredients"), ("glob", "🧺 Hunting for ingredients"),
                     ("task", "🛎️ Ordering the cooks"), ("fetch", "🚚 Supplier delivery"),
                     ("ask_user", "💬 Waiting on the customer")]
        case .prison:
            table = [("bash", "📢 Calling the yard drill"), ("edit", "🖊️ Signing work orders"), ("create", "🏗️ Building a new wing"),
                     ("view", "🔦 Inspecting the cells"), ("grep", "🔎 Searching the cells"), ("glob", "🔎 Searching the cells"),
                     ("task", "📋 Assigning community service"), ("fetch", "📞 Calling the courthouse"),
                     ("ask_user", "💬 Awaiting the parole board")]
        case .football:
            table = [("bash", "🏃 Sprint training"), ("edit", "🥅 Taking a shot"), ("create", "🏟️ Building a new stand"),
                     ("view", "👀 Watching the replay"), ("grep", "🔎 Scouting the opposition"), ("glob", "🔎 Scouting the opposition"),
                     ("task", "📣 Calling a substitution"), ("fetch", "📞 Phoning the club"),
                     ("ask_user", "💬 Waiting for the VAR")]
        case .farm:
            table = [("bash", "💧 Drinking at the trough"), ("edit", "✂️ Getting sheared"), ("create", "🏡 Building a pen"),
                     ("view", "👀 Looking around"), ("grep", "🌾 Foraging"), ("glob", "🌾 Foraging"),
                     ("task", "📣 Calling the flock"), ("fetch", "🚜 Hay delivery"),
                     ("ask_user", "💬 Awaiting the farmer")]
        case .impostor:
            table = [("bash", "⛽ Fueling the engines"), ("edit", "🔌 Fixing the wires"), ("create", "🛠️ Building a vent"),
                     ("view", "📥 Downloading data"), ("grep", "🕵️ Checking the cameras"), ("glob", "🕵️ Checking the cameras"),
                     ("task", "📣 Calling a meeting"), ("fetch", "📡 Contacting mission control"),
                     ("ask_user", "💬 Waiting for the vote")]
        case .wizard:
            table = [("bash", "🧪 Brewing a potion"), ("edit", "🪄 Casting a spell"), ("create", "🏰 Conjuring a new tower"),
                     ("view", "📚 Reading the spellbook"), ("grep", "🔮 Peering into the crystal ball"), ("glob", "🔮 Peering into the crystal ball"),
                     ("task", "🦉 Summoning an apprentice"), ("fetch", "🦉 Waiting for the owl post"),
                     ("ask_user", "💬 Awaiting the headwizard")]
        case .galactic:
            table = [("bash", "🚀 Firing the hyperdrive"), ("edit", "🤖 Repairing a bot"), ("create", "🛠️ Building a new cruiser"),
                     ("view", "🔭 Scanning the sector"), ("grep", "🛰️ Sweeping for signals"), ("glob", "🛰️ Sweeping for signals"),
                     ("task", "📣 Dispatching a cadet"), ("fetch", "📡 Hailing the outpost"),
                     ("ask_user", "💬 Awaiting the admiral")]
        case .fellowship:
            table = [("bash", "🔥 Cooking over the campfire"), ("edit", "⚒️ Hammering at the forge"), ("create", "🏕️ Setting up camp"),
                     ("view", "🗺️ Studying the map"), ("grep", "🏹 Tracking the trail"), ("glob", "🏹 Tracking the trail"),
                     ("task", "📯 Sounding the horn"), ("fetch", "🦅 Waiting for the eagle"),
                     ("ask_user", "💬 Awaiting the wise guide")]
        }
        for (key, text) in table where t.contains(key) { return text }
        return "⚡️ \(tool)"
    }
}
