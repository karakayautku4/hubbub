import SceneKit
import AppKit

/// Cheap, capped particle systems for ambience weather. Emitter boxes cover the playfield seen by the stage camera.
@MainActor
enum Weather {
    private static func dot(_ size: Int, soft: Bool) -> NSImage {
        Gfx.image(size, size) { c in
            let r = CGFloat(size)
            if soft {
                let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                c.drawRadialGradient(g, startCenter: CGPoint(x: r / 2, y: r / 2), startRadius: 0, endCenter: CGPoint(x: r / 2, y: r / 2), endRadius: r / 2, options: [])
            } else {
                c.setFillColor(NSColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: 0, y: 0, width: r, height: r))
            }
        }
    }

    private static func base(rate: CGFloat, life: CGFloat, size: CGFloat, box: SCNVector3, image: NSImage) -> SCNParticleSystem {
        let p = SCNParticleSystem()
        p.birthRate = rate
        p.particleLifeSpan = life
        p.particleLifeSpanVariation = life * 0.2
        p.particleSize = size
        p.particleImage = image
        p.emitterShape = SCNBox(width: CGFloat(box.x), height: CGFloat(box.y), length: CGFloat(box.z), chamferRadius: 0)
        p.birthLocation = .volume
        p.birthDirection = .random
        p.loops = true
        p.isLightingEnabled = false
        p.blendMode = .alpha
        p.warmupDuration = life
        p.isLocal = false
        return p
    }

    static func rain(rate: CGFloat) -> SCNParticleSystem {
        let p = base(rate: rate, life: 1.1, size: 0.05, box: SCNVector3(44, 0.5, 30), image: dot(8, soft: false))
        p.emittingDirection = SCNVector3(0.12, -1, 0)
        p.speedFactor = 1
        p.particleVelocity = 22
        p.particleVelocityVariation = 3
        p.birthDirection = .constant
        p.stretchFactor = 0.07
        p.particleColor = NSColor(red: 0.75, green: 0.85, blue: 1, alpha: 0.5)
        return p
    }

    static func snow(rate: CGFloat) -> SCNParticleSystem {
        let p = base(rate: rate, life: 8, size: 0.14, box: SCNVector3(44, 0.5, 30), image: dot(16, soft: true))
        p.emittingDirection = SCNVector3(0.1, -1, 0)
        p.birthDirection = .constant
        p.particleVelocity = 1.6
        p.particleVelocityVariation = 0.6
        p.particleColor = NSColor(white: 1, alpha: 0.9)
        p.acceleration = SCNVector3(0.25, 0, 0.1)
        return p
    }

    static func fireflies(rate: CGFloat) -> SCNParticleSystem {
        let p = base(rate: rate, life: 4, size: 0.16, box: SCNVector3(30, 2.4, 18), image: dot(16, soft: true))
        p.particleVelocity = 0.5
        p.particleVelocityVariation = 0.4
        p.particleColor = NSColor(red: 1, green: 0.9, blue: 0.4, alpha: 1)
        p.particleColorVariation = SCNVector4(0.1, 0.1, 0.1, 0)
        p.blendMode = .additive
        p.particleIntensity = 1.6
        p.particleSizeVariation = 0.08
        let fade = SCNParticlePropertyController(animation: {
            let a = CAKeyframeAnimation()
            a.values = [0, 1, 0.3, 1, 0]
            a.keyTimes = [0, 0.2, 0.5, 0.8, 1]
            a.duration = 1
            return a
        }())
        p.propertyControllers = [.opacity: fade]
        return p
    }
}
