import SceneKit

/// Limb/body offsets of one job animation frame. Pure maths, so it is cheap and shared by humans and sheep.
struct JobPose {
    var bodyX: CGFloat = 0, bodyZ: CGFloat = 0, lift: CGFloat = 0
    var headX: CGFloat = 0, headY: CGFloat = 0
    var aL = SCNVector3Zero, aR = SCNVector3Zero
    var lL: CGFloat = 0, lR: CGFloat = 0
    /// Offset of the whole figure on the ground (for animations that move around the spot).
    var dx: CGFloat = 0, dz: CGFloat = 0
}

extension JobAnim {
    /// Pose at time `t`; `v` is a per-agent phase so neighbours do not move in lockstep.
    func pose(t tt: CGFloat, v: CGFloat) -> JobPose {
        var p = JobPose()
        let t = tt + v * 0.37
        switch self {
        case .type:
            p.aL.x = -1.3 + sin(t * 17) * 0.12; p.aR.x = -1.3 + sin(t * 15 + 1) * 0.12; p.headX = 0.12; p.headY = sin(t * 0.9) * 0.15
        case .hammer:
            p.aR.x = -1.6 + sin(t * 8) * 1.0; p.aL.x = -0.9; p.bodyX = 0.1 + sin(t * 8) * 0.06
        case .stir:
            p.aR.x = -1.35; p.aR.z = sin(t * 7) * 0.5; p.aL.x = -0.8; p.headX = 0.3
        case .sweep:
            p.aL.x = -1.0; p.aR.x = -1.0; p.bodyX = 0.18 + sin(t * 4) * 0.08
            p.aL.z = sin(t * 4) * 0.35; p.aR.z = sin(t * 4) * 0.35; p.dx = sin(t * 2) * 0.12
        case .polish:
            p.aR.x = -1.5 + sin(t * 5) * 0.2; p.aR.z = cos(t * 5) * 0.5; p.aL.x = -1.0; p.bodyX = 0.15; p.headX = 0.3
        case .juggle:
            p.aL.x = -1.6 + sin(t * 9) * 0.9; p.aR.x = -1.6 - sin(t * 9) * 0.9; p.headY = sin(t * 4.5) * 0.3; p.headX = -0.3
            p.lift = abs(sin(t * 4.5)) * 0.05
        case .stack:
            let s = sin(t * 2.2)
            p.bodyX = 0.35 + s * 0.35; p.aL.x = -1.2 + s * 0.5; p.aR.x = -1.2 + s * 0.5; p.headX = -0.15
        case .wrench:
            p.aR.x = -2.0; p.aR.z = sin(t * 6) * 0.6; p.aL.x = -1.2 + sin(t * 6 + 1) * 0.2; p.bodyX = -0.08; p.headX = -0.25
        case .water:
            p.aR.x = -1.4; p.aR.z = -0.2 + sin(t * 1.5) * 0.1; p.aL.x = -0.2; p.headX = 0.3; p.bodyX = 0.1 + sin(t * 1.5) * 0.05
        case .yoga:
            p.lift = 0.5 + sin(t * 1.2) * 0.15; p.aL.z = 2.0; p.aR.z = -2.0; p.lL = 0.55; p.lR = -0.55
            p.bodyZ = sin(t * 0.6) * 0.1; p.headX = -0.1
        case .scan:
            p.aR.x = -2.5; p.aL.x = 0.1; p.headY = sin(t * 1.2) * 0.8; p.headX = 0.05
        case .dig:
            let s = sin(t * 5)
            p.bodyX = 0.5 + s * 0.25; p.aL.x = -1.0 + s * 0.7; p.aR.x = -1.0 + s * 0.7; p.headX = 0.2
        case .pushups:
            p.bodyX = 0.95; p.lift = -0.05 + 0.3 * abs(sin(t * 3)); p.aL.x = -0.3; p.aR.x = -0.3; p.lL = -0.5; p.lR = -0.5; p.headX = -0.6
        case .cards:
            p.aL.x = -1.1; p.aR.x = -1.1 + max(0, sin(t * 1.7)) * 0.7; p.headX = 0.4; p.headY = sin(t * 0.8) * 0.3
        case .dance:
            let s = sin(t * 6)
            p.lift = abs(s) * 0.25; p.bodyZ = s * 0.2; p.aL.z = 2.2 + s * 0.6; p.aR.z = -2.2 + s * 0.6
            p.headY = sin(t * 3) * 0.4; p.dx = sin(t * 1.5) * 0.3
        case .pump:
            p.bodyX = 0.4 + sin(t * 6) * 0.1; p.aR.x = -0.6 + sin(t * 6) * 0.7; p.aL.x = -0.6; p.headX = 0.2
        case .paint:
            p.aR.x = -2.6 + sin(t * 3.5) * 0.5; p.aR.z = sin(t * 3.5) * 0.3; p.aL.x = 0.2; p.headX = -0.15
        case .spell:
            p.aR.x = -2.4 + sin(t * 4) * 0.4; p.aR.z = sin(t * 2) * 0.5; p.aL.x = -0.3; p.headX = -0.2
            p.lift = max(0, sin(t * 2)) * 0.15
        case .read:
            p.aL.x = -1.35; p.aR.x = -1.35; p.headX = 0.5 + sin(t * 0.7) * 0.1; p.headY = sin(t * 0.9) * 0.15
        case .tinker:
            p.aL.x = -1.2 + sin(t * 13) * 0.12; p.aR.x = -1.3 + sin(t * 11 + 1) * 0.2; p.headX = 0.4; p.bodyX = 0.25
        case .aim:
            p.aR.x = -1.55 + (sin(t * 3.5) > 0.9 ? 0.25 : 0); p.aL.x = -0.2; p.headY = 0.1
        case .plot:
            p.aR.x = -1.7 + sin(t * 1.3) * 0.3; p.aR.z = sin(t * 1.1) * 0.6; p.aL.x = -1.0; p.headX = 0.35
        case .smoke:
            p.aR.x = -1.25 - 1.0 * sin(t * 0.9); p.bodyX = -0.1; p.headX = -0.15; p.bodyZ = sin(t * 0.5) * 0.03
        case .flip:
            p.aR.x = -1.5 - sin(t * 4) * 1.2; p.aL.x = -0.3; p.headX = -0.3
        case .peel:
            p.aL.x = -1.3; p.aR.x = -1.3 + sin(t * 7) * 0.4; p.headX = 0.5; p.bodyX = 0.15
        case .taste:
            let s = sin(t * 0.9)
            p.aR.x = -1.0 - 1.3 * max(0, s); p.aR.z = max(0, -s) * sin(t * 7) * 0.4; p.aL.x = -0.8; p.headX = 0.1 + max(0, s) * 0.2
        case .wash:
            p.bodyX = 0.35; p.aL.x = -1.2; p.aR.x = -1.2; p.aL.z = sin(t * 6) * 0.5; p.aR.z = -sin(t * 6) * 0.5; p.headX = 0.4
        case .chase:
            let a = t * 1.1
            p.dx = sin(a) * 1.1; p.dz = cos(a) * 0.7 - 0.7
            p.lL = sin(t * 10) * 0.7; p.lR = -sin(t * 10) * 0.7; p.aL.x = sin(t * 10) * 0.7; p.aR.x = -sin(t * 10) * 0.7
            p.bodyX = 0.2; p.lift = abs(sin(t * 10)) * 0.07
        case .milk:
            p.bodyX = 0.5; p.aL.x = -1.1 + sin(t * 6) * 0.4; p.aR.x = -1.1 - sin(t * 6) * 0.4; p.headX = -0.1
        }
        return p
    }
}
