import SceneKit
import AppKit

/// Arena growth, job props and zoom handling for the stage.
extension Stage {
    func updateArena(sim: RoomSim, t: Double) {
        let dt = min(max(t - (lastArenaT ?? t), 0), 0.1)
        lastArenaT = t
        let snap = A11y.reduceMotion
        let slots = sim.all.filter { $0.phase != .leaving }.map(\.jobSlot)
        arena.ease(toward: Jobs.extent(of: slots, theme: theme), dt: dt, snap: snap)
        arenaExt.update(xHalf: arena.xHalf, dt: dt, snap: snap)
        syncJobProps(sim: sim, t: t)
        let size = view?.bounds.size ?? CGSize(width: 636, height: 358)
        // The race strip lies in the foreground, beyond the job area.
        let frame = ArenaMath.frame(xHalf: arena.xHalf, zFar: fun.race.isActive ? max(arena.zFar, 13.6) : arena.zFar, aspect: size.width / max(size.height, 1))
        cameraRig.fitTarget = frame.fit
        cameraRig.tiltTarget = frame.tilt
        cameraRig.userZoomTarget = zoomLevel
        cameraRig.arenaHalfWidth = arena.xHalf
        cameraRig.lookShiftZ = frame.shift
        let labelTarget = min(max(pow(cameraRig.distanceMultiplier, 0.45), 0.9), 1.7) * (sim.all.count > 20 ? 0.7 : sim.all.count > 12 ? 0.82 : 1)
        labelScale += (labelTarget - labelScale) * (A11y.reduceMotion ? 1 : 0.15)
    }

    /// Creates a prop for every occupied job spot and fades out props whose spot became free.
    private func syncJobProps(sim: RoomSim, t: Double) {
        let slots = sim.jobSlots
        let jobs = Jobs.catalog(for: theme)
        var want = Set<Int>()
        for a in sim.all where a.phase != .leaving && a.phase != .finishing && slots.indices.contains(a.jobSlot) { want.insert(a.jobSlot) }
        for (slot, node) in jobProps where !want.contains(slot) {
            jobFades[slot] = (node, t)
            jobProps[slot] = nil
        }
        for (slot, f) in jobFades {
            if want.contains(slot) { jobProps[slot] = f.node; jobFades[slot] = nil; continue }
            let k = 1 - (t - f.since) / 0.5
            if k <= 0 { f.node.removeFromParentNode(); jobFades[slot] = nil } else { f.node.opacity = CGFloat(k) }
        }
        for (slot, node) in jobProps where node.opacity < 1 { node.opacity = CGFloat(min(1, (t - (jobBirth[slot] ?? t)) / 0.6)) }
        for slot in want where jobProps[slot] == nil {
            let s = slots[slot]
            let g = SCNNode()
            g.name = "jobprop"
            g.position = SCNVector3(Environments.wx(s.pos.x), 0, Environments.wz(s.pos.y))
            g.eulerAngles = SCNVector3(0, Jobs.facing(atLogicalX: s.pos.x), 0)
            jobs[s.jobIndex % jobs.count].prop(g)
            g.opacity = 0
            jobBirth[slot] = t
            jobsRoot.addChildNode(g)
            jobProps[slot] = g
        }
    }

    // MARK: Zoom

    func setZoom(_ z: CGFloat) {
        let v = ArenaMath.clampZoom(z)
        guard v != zoomLevel else { return }
        zoomLevel = v
        noteInteraction()
        remember()
        cameraRig.poke(t: now)
    }

    func zoomBy(direction: Int) { setZoom(ArenaMath.steppedZoom(zoomLevel, direction: direction)) }
    func resetZoom() { setZoom(1) }

    func scrollZoom(delta: CGFloat) { setZoom(ArenaMath.zoom(zoomLevel, scrollDelta: delta)) }
    func pinchZoom(magnification: CGFloat) { setZoom(ArenaMath.zoom(zoomLevel, magnification: magnification)) }

    private func remember() {
        let key = selectedSessionID.flatMap { id in sessions.contains { $0.id == id } ? id : nil } ?? sessions.first?.id ?? "__empty"
        if zoomLevel == 1 { zoomBySession[key] = nil } else { zoomBySession[key] = zoomLevel }
    }

    /// Arena state for tests and diagnostics.
    var arenaExtent: (xHalf: CGFloat, zFar: CGFloat) { (arena.xHalf, arena.zFar) }
    var jobPropCount: Int { jobProps.count }
}
