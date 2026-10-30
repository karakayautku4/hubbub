import SceneKit
import AppKit

extension Rig {
    /// Adds the level-gated cosmetics (see `Progression.cosmetics`) to the captain: a spinning star hat,
    /// tinted by the best unlocked colour, plus an optional sparkle orbit.
    func applyProgressionCosmetics() {
        let owned = Progression.unlockedCosmetics
        guard owned.contains("hat.star") else { return }
        let hex: UInt32 = owned.contains("color.violet") ? 0xb27dff : owned.contains("color.gold") ? 0xffc93c
            : owned.contains("color.cyan") ? 0x3fe0ff : 0xffe066
        let mat = Gfx.mat(hex, r: 0.3, e: hex)

        let star = SCNNode()
        star.position = SCNVector3(0, 0.82, 0)
        for angle in [0.0, 45.0] {
            let arm = star.box(0.34, 0.07, 0.07, mat, 0, 0, 0)
            arm.eulerAngles.z = CGFloat(angle * .pi / 180)
            let cross = star.box(0.34, 0.07, 0.07, mat, 0, 0, 0)
            cross.eulerAngles.z = CGFloat((angle + 90) * .pi / 180)
        }
        star.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3)))
        head.addChildNode(star)

        guard owned.contains("trail.sparkle") else { return }
        let orbit = SCNNode()
        orbit.position = SCNVector3(0, 0.3, 0)
        for i in 0..<3 {
            let a = Double(i) * 2 * .pi / 3
            orbit.ball(0.035, mat, CGFloat(cos(a)) * 0.5, CGFloat(sin(a * 2)) * 0.08, CGFloat(sin(a)) * 0.5)
        }
        orbit.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 2.2)))
        head.addChildNode(orbit)
    }
}
