import SceneKit
import SwiftUI

enum CameraMode: String, CaseIterable, Identifiable {
    case free, follow, cinematic
    var id: String { rawValue }
    var title: String { switch self { case .free: "Free"; case .follow: "Follow"; case .cinematic: "Cinematic" } }
    var icon: String { switch self { case .free: "viewfinder"; case .follow: "scope"; case .cinematic: "film" } }
    var blurb: String {
        switch self {
        case .free: "Drag the scene to orbit, right-drag or ⌥-drag to pan, scroll to zoom. The fit button resets the view."
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
    /// User-controlled view on top of the free camera: orbit angles (radians) and a ground pan; eased like the fit.
    var orbitYawTarget: CGFloat = 0
    var orbitPitchTarget: CGFloat = 0
    var panTarget = CGPoint.zero
    private var orbitYaw: CGFloat = 0
    private var orbitPitch: CGFloat = 0
    private var panCur = CGPoint.zero
    private var fwd = CGPoint(x: 0, y: -1)
    static let maxPan = CGPoint(x: 14, y: 9)
    var viewIsDefault: Bool { orbitYawTarget == 0 && orbitPitchTarget == 0 && panTarget == .zero }

    func orbit(dx: CGFloat, dy: CGFloat) {
        orbitYawTarget = min(max(orbitYawTarget - dx * 0.008, -1.4), 1.4)
        orbitPitchTarget = min(max(orbitPitchTarget + dy * 0.006, -0.35), 0.75)
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        let k: CGFloat = 0.035 * distanceMultiplier / userZoom
        let right = CGPoint(x: -fwd.y, y: fwd.x)
        panTarget.x += (-dx * right.x + dy * fwd.x) * k
        panTarget.y += (-dx * right.y + dy * fwd.y) * k
        panTarget.x = min(max(panTarget.x, -Self.maxPan.x), Self.maxPan.x)
        panTarget.y = min(max(panTarget.y, -Self.maxPan.y), Self.maxPan.y)
    }

    func resetView() { orbitYawTarget = 0; orbitPitchTarget = 0; panTarget = .zero }

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
        orbitYaw += (orbitYawTarget - orbitYaw) * ez
        orbitPitch += (orbitPitchTarget - orbitPitch) * ez
        panCur.x += (panTarget.x - panCur.x) * ez
        panCur.y += (panTarget.y - panCur.y) * ez
        var wantPos: SCNVector3, wantLook: SCNVector3, rate: Double
        var userView = false
        switch mode {
        case .free:
            wantPos = scaled(hoverNX * 1.4, 14.2, 22.8)
            wantLook = SCNVector3(hoverNX * 0.4, 0, base.z)
            rate = 8
            userView = true
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
                    userView = true
                } else {
                    let a = 0.55 * sin(t * 0.11)
                    let r = (21 + 3 * sin(t * 0.07)) * m
                    wantPos = SCNVector3(sin(a) * r, (11 + 2.5 * sin(t * 0.05)) * m, base.z + cos(a) * r)
                    wantLook = SCNVector3(0, 0, base.z)
                    rate = 1.5
                }
            }
        }
        if userView {
            wantLook.x += panCur.x; wantLook.z += panCur.y
            var ox = wantPos.x - wantLook.x + panCur.x, oy = wantPos.y, oz = wantPos.z - wantLook.z + panCur.y
            let r = max(sqrt(ox * ox + oy * oy + oz * oz), 0.001)
            let az = atan2(ox, oz) + orbitYaw
            let el = min(max(asin(oy / r) + orbitPitch, 0.12), 1.45)
            ox = r * cos(el) * sin(az); oy = r * sin(el); oz = r * cos(el) * cos(az)
            wantPos = SCNVector3(wantLook.x + ox, oy, wantLook.z + oz)
            let fl = hypot(ox, oz)
            if fl > 0.01 { fwd = CGPoint(x: -ox / fl, y: -oz / fl) }
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
