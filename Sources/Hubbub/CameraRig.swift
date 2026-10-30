import SceneKit
import SwiftUI

enum CameraMode: String, CaseIterable, Identifiable {
    case free, follow, cinematic
    var id: String { rawValue }
    var title: String { switch self { case .free: "Free"; case .follow: "Follow"; case .cinematic: "Cinematic" } }
    var icon: String { switch self { case .free: "viewfinder"; case .follow: "scope"; case .cinematic: "film" } }
    var blurb: String {
        switch self {
        case .free: "Fixed view with a gentle parallax that follows your pointer."
        case .follow: "Smoothly follows the selected character. Double-click a character to toggle."
        case .cinematic: "Slow orbit that cuts to spawns, failures and celebrations. Pauses while you interact."
        }
    }
    static let storageKey = "cameraMode"
    static var current: CameraMode {
        get { CameraMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .free }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
    var next: CameraMode { let all = CameraMode.allCases; return all[(all.firstIndex(of: self)! + 1) % all.count] }
}

/// Smooth camera controller. Only advanced from the render tick, so it costs nothing while the popover is hidden.
@MainActor
final class CameraRig {
    var hoverNX: CGFloat = 0
    var followID: String?
    private var pos = SCNVector3(0, 14.2, 22.8)
    private var look = SCNVector3(0, 0, 3.5)
    private var zoom: CGFloat = 1
    private var zoomTarget: CGFloat = 1
    /// Auto-framing factor for the current arena size and the user zoom (1 = fitted); both ease toward their targets.
    var fitTarget: CGFloat = 1
    var userZoomTarget: CGFloat = 1
    var arenaHalfWidth: CGFloat = 14.6
    var lookShiftZ: CGFloat = 0
    /// Camera height factor of the free view (1 = classic pitch); eased like the fit.
    var tiltTarget: CGFloat = 1
    private var tilt: CGFloat = 1
    private var fit: CGFloat = 1
    private var userZoom: CGFloat = 1
    /// Distance multiplier relative to the base framing (>1 = farther away).
    var distanceMultiplier: CGFloat { fit / userZoom }
    private var lastT: Double?
    private var lastPoke = -100.0
    private var shot: (target: SCNVector3, until: Double)?

    /// Pointer activity pauses the cinematic orbit for a few seconds.
    func poke(t: Double) { lastPoke = t }

    func focus(_ zoomed: Bool) { zoomTarget = zoomed ? 0.72 : 1 }

    /// Hard cut to a close shot of `world` that eases in; cinematic mode only.
    func cut(to world: SCNVector3, t: Double, hold: Double = 4.5) {
        guard CameraMode.current == .cinematic, !A11y.reduceMotion, t - lastPoke > 6 else { return }
        shot = (world, t + hold)
        pos = SCNVector3(world.x + 5, world.y + 6.5, world.z + 11)
        look = SCNVector3(world.x, world.y + 1, world.z)
    }

    private static func mix(_ a: SCNVector3, _ b: SCNVector3, _ k: CGFloat) -> SCNVector3 {
        SCNVector3(a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k)
    }

    func update(_ node: SCNNode, t: Double, follow: SCNVector3?) {
        let dt = min(max(t - (lastT ?? t), 0), 0.1)
        lastT = t
        // Reduce Motion: no orbit, cuts or pointer parallax.
        let reduce = A11y.reduceMotion
        let mode = reduce && CameraMode.current == .cinematic ? CameraMode.free : CameraMode.current
        let hoverNX = reduce ? 0 : self.hoverNX
        let ez = CGFloat(reduce ? 1 : 1 - exp(-dt * 6))
        fit += (fitTarget - fit) * ez
        tilt += (tiltTarget - tilt) * ez
        userZoom += (userZoomTarget - userZoom) * ez
        let m = distanceMultiplier
        let base = SCNVector3(0, 0, 3.5 + lookShiftZ)
        func scaled(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> SCNVector3 { SCNVector3(x, y * m * tilt, base.z + (z - 3.5) * m) }
        var wantPos: SCNVector3, wantLook: SCNVector3, rate: Double
        switch mode {
        case .free:
            wantPos = scaled(hoverNX * 1.4, 14.2, 22.8)
            wantLook = SCNVector3(hoverNX * 0.4, 0, base.z)
            rate = 8
        case .follow:
            let tp = follow ?? SCNVector3(0, 0, 3.5)
            let z = zoom / userZoom
            let lim = max(15, arenaHalfWidth)
            wantPos = SCNVector3(min(max(tp.x, -lim), lim), 7.5 * z + 1.5, tp.z + 12.5 * z)
            wantLook = SCNVector3(min(max(tp.x, -lim), lim), 0.8, tp.z)
            rate = 3.5
        case .cinematic:
            if let s = shot, t < s.until, t - lastPoke > 6 {
                wantPos = SCNVector3(s.target.x + 1.5 / userZoom, s.target.y + 4.2 / userZoom, s.target.z + 8 / userZoom)
                wantLook = SCNVector3(s.target.x, s.target.y + 1, s.target.z)
                rate = 2.5
            } else {
                shot = nil
                if t - lastPoke < 6 {
                    wantPos = scaled(hoverNX * 1.4, 14.2, 22.8)
                    wantLook = SCNVector3(hoverNX * 0.4, 0, base.z)
                    rate = 3
                } else {
                    let a = 0.55 * sin(t * 0.11)
                    let r = (21 + 3 * sin(t * 0.07)) * m
                    wantPos = SCNVector3(sin(a) * r, (11 + 2.5 * sin(t * 0.05)) * m, base.z + cos(a) * r)
                    wantLook = SCNVector3(0, 0, base.z)
                    rate = 1.5
                }
            }
        }
        let k = CGFloat(1 - exp(-dt * rate))
        zoom += (zoomTarget - zoom) * CGFloat(1 - exp(-dt * 3))
        pos = CameraRig.mix(pos, wantPos, k)
        look = CameraRig.mix(look, wantLook, k)
        node.position = pos
        node.look(at: look)
    }
}

/// Settings > Appearance card for the persisted camera mode.
struct CameraModePicker: View {
    @AppStorage(CameraMode.storageKey) private var raw = CameraMode.free.rawValue
    var body: some View {
        SettingsCard(title: "Camera", footer: (CameraMode(rawValue: raw) ?? .free).blurb) {
            Picker("Camera", selection: $raw) {
                ForEach(CameraMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

/// Small corner control for switching camera mode (also bound to the C key).
struct CameraModeButton: View {
    @AppStorage(CameraMode.storageKey) private var raw = CameraMode.free.rawValue
    var body: some View {
        let mode = CameraMode(rawValue: raw) ?? .free
        Button { raw = mode.next.rawValue } label: {
            Image(systemName: mode.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Camera: \(mode.title) (press C to switch)")
        .accessibilityLabel("Camera mode: \(mode.title)")
        .padding(8)
        .opacity(0.8)
    }
}
