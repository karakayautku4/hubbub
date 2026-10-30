import SceneKit
import AppKit

extension RoomSim {
    /// Gentle reaction to petting: happy emote plus a cute line.
    func pet(_ id: String, t: Double) {
        let lines = ["Aww, thanks! 💕", "Hehe, that tickles!", "Best human ever 💖", "Purr… 🥰", "More pets, please!"]
        mutate(id) {
            guard !$0.dragged else { return }
            $0.mood = .celebrate
            $0.moodUntil = t + 1.8
            $0.say = lines.randomElement()
            $0.sayUntil = t + 2.4
        }
    }

    /// After a drop: if the character landed near a station, send it there to do that station's job.
    @discardableResult
    func goToNearestStation(_ id: String, t: Double, within radius: CGFloat = 26) -> Bool {
        guard let a = all.first(where: { $0.id == id }), a.phase != .leaving else { return false }
        let stations = theme.stations
        guard let i = stations.indices.min(by: { hypot(stations[$0].pos.x - a.pos.x, stations[$0].pos.y - a.pos.y) < hypot(stations[$1].pos.x - a.pos.x, stations[$1].pos.y - a.pos.y) }),
              hypot(stations[i].pos.x - a.pos.x, stations[i].pos.y - a.pos.y) <= radius else { return false }
        let st = stations[i]
        let target = a.isCaptain ? st.pos : stationTarget(i, excluding: id)
        mutate(id) {
            $0.mood = .none
            $0.moodUntil = t
            $0.say = "\(st.emoji) \(st.label)"
            $0.sayUntil = t + 3
            $0.route = [target]
            if $0.isCaptain {
                $0.onJob = false
                $0.pauseUntil = t + 6
            } else {
                $0.station = i
                $0.kind = i
                $0.onJob = false
                $0.phase = .arriving
                $0.lastSwitch = t + 6
            }
        }
        return true
    }
}

extension Stage {
    static let propEmoji: [String: String] = [
        "coffee": "☕️", "radar": "📡", "rack": "💾", "wallmap": "🗺️", "console": "🎛️", "planet": "🪐", "reactor": "⚡️", "airlock": "🚪",
        "stove": "🔥", "bell": "🔔", "pass": "🍽️", "alarm": "🚨", "gate": "🔑", "desk": "📋", "goal": "⚽️", "ball": "⚽️", "var": "📺",
        "barn": "🐑", "windmill": "🌬️", "scarecrow": "🐦"
    ]

    /// Floats an emoji upward from a world position and fades it out.
    func floatEmoji(_ emoji: String, at p: SCNVector3, size: CGFloat = 40, rise: CGFloat = 2.2) {
        let img = Gfx.label(emoji, size: size, fg: .white, bg: .clear)
        let n = Gfx.billboard(img, unitsPerPoint: 0.012)
        n.position = p
        n.opacity = 0
        scene.rootNode.addChildNode(n)
        let drift = CGFloat.random(in: -0.5...0.5)
        n.runAction(.sequence([
            .group([.fadeIn(duration: 0.15), .moveBy(x: drift, y: rise, z: 0, duration: 1.3), .sequence([.wait(duration: 0.8), .fadeOut(duration: 0.5)])]),
            .removeFromParentNode()
        ]))
    }

    func puff(prop: String, at node: SCNNode) {
        guard let e = Stage.propEmoji[prop] ?? (prop.hasPrefix("cell") ? "🔒" : nil) else { return }
        let w = node.worldPosition
        floatEmoji(e, at: SCNVector3(w.x, w.y + 2.2, w.z), size: 34, rise: 1.4)
    }

    func hearts(forActor id: String) {
        guard let root = rigs[id]?.root else { return }
        let p = root.position
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.18) { [weak self] in
                self?.floatEmoji(["❤️", "💖", "💕", "✨"][i], at: SCNVector3(p.x + CGFloat.random(in: -0.4...0.4), 2.6, p.z), size: 36)
            }
        }
    }

    func petActor(_ id: String) {
        currentSim?.pet(id, t: now)
        hearts(forActor: id)
        Feedback.play("Pop")
    }

    func cycleCameraMode() {
        CameraMode.current = CameraMode.current.next
        cameraRig.poke(t: now)
    }
}
