import SwiftUI

/// Halloween frame for the app UI: corner cobwebs, a spider, bats, a glowing jack-o'-lantern, a skull and an orange tint. Decorative only.
struct HalloweenChrome: ViewModifier {
    @AppStorage(Halloween.key) private var modeRaw = HalloweenMode.auto.rawValue
    @Environment(\.colorScheme) private var scheme

    private var on: Bool { Halloween.isActive(mode: Halloween.mode(from: modeRaw)) }
    private var accent: Color { scheme == .dark ? Color(red: 1, green: 0.55, blue: 0.14) : Color(red: 0.86, green: 0.38, blue: 0.02) }

    func body(content: Content) -> some View {
        if on {
            content
                .tint(accent)
                .overlay { decorations.allowsHitTesting(false).accessibilityHidden(true) }
        } else {
            content
        }
    }

    private var decorations: some View {
        GeometryReader { geo in
            let w = min(max(geo.size.width * 0.21, 70), 110)
            let ink = scheme == .dark ? Color.white : Color.black
            let calm = A11y.increaseContrast
            ZStack(alignment: .topLeading) {
                if !calm {
                    CobwebShape().stroke(ink.opacity(0.42), lineWidth: 1.4)
                        .frame(width: w, height: w * 0.5)
                    CobwebShape().stroke(ink.opacity(0.42), lineWidth: 1.4)
                        .frame(width: w, height: w * 0.5)
                        .scaleEffect(x: -1)
                        .position(x: geo.size.width - w / 2, y: w * 0.25)
                    Spider(ink: ink)
                        .frame(width: 18, height: 52)
                        .position(x: geo.size.width - 9, y: 30)
                    BatShape().fill(Color.purple.opacity(0.9)).frame(width: 18, height: 12)
                        .position(x: geo.size.width * 0.42, y: 8)
                    BatShape().fill(Color.purple.opacity(0.75)).frame(width: 12, height: 8)
                        .rotationEffect(.degrees(-12))
                        .position(x: geo.size.width * 0.58, y: 6)
                }
                JackOLantern().frame(width: 58, height: 48)
                    .scaleEffect(0.85)
                    .position(x: 24, y: geo.size.height - 20)
                SkullShape().frame(width: 28, height: 28)
                    .scaleEffect(0.85)
                    .position(x: geo.size.width - 18, y: geo.size.height - 14)
            }
        }
    }
}

extension View {
    func halloweenChrome() -> some View { modifier(HalloweenChrome()) }
}

/// Quarter cobweb hanging from the top-left corner of its frame.
struct CobwebShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height)
        func pt(_ rad: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rad * cos(a), y: rect.minY + rad * sin(a)) }
        let strands = 5
        let angles = (0..<strands).map { CGFloat($0) / CGFloat(strands - 1) * .pi / 2 }
        for a in angles { p.move(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: pt(r, a)) }
        for k in 1...4 {
            let rad = r * CGFloat(k) / 4
            for i in 0..<(strands - 1) {
                p.move(to: pt(rad, angles[i]))
                p.addQuadCurve(to: pt(rad, angles[i + 1]), control: pt(rad * 0.8, (angles[i] + angles[i + 1]) / 2))
            }
        }
        return p
    }
}

struct BatShape: Shape {
    func path(in rect: CGRect) -> Path {
        let half: [(CGFloat, CGFloat)] = [(0.5, 0.78), (0.6, 0.6), (0.72, 0.78), (0.82, 0.56), (0.95, 0.68), (1, 0.1), (0.78, 0.3), (0.6, 0.32), (0.56, 0.02), (0.5, 0.2)]
        let pts = half + half.dropFirst().dropLast().reversed().map { (1 - $0.0, $0.1) }
        var p = Path()
        for (i, q) in pts.enumerated() {
            let c = CGPoint(x: rect.minX + q.0 * rect.width, y: rect.minY + q.1 * rect.height)
            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
        }
        p.closeSubpath()
        return p
    }
}

/// Hanging spider; the frame is 18 x 52 with the thread running from the top.
struct Spider: View {
    let ink: Color
    var body: some View {
        Canvas { c, size in
            let cx = size.width / 2, by: CGFloat = 40
            var p = Path()
            p.move(to: CGPoint(x: cx, y: 0)); p.addLine(to: CGPoint(x: cx, y: by - 4))
            c.stroke(p, with: .color(ink.opacity(0.6)), lineWidth: 1)
            var legs = Path()
            for i in 0..<4 {
                let dy = CGFloat(i) * 2.6 - 3.5
                for sx: CGFloat in [-1, 1] {
                    legs.move(to: CGPoint(x: cx, y: by + dy * 0.4))
                    legs.addLine(to: CGPoint(x: cx + sx * 6, y: by + dy - 2))
                    legs.addLine(to: CGPoint(x: cx + sx * 8.5, y: by + dy + 3))
                }
            }
            c.stroke(legs, with: .color(.black.opacity(0.85)), lineWidth: 1)
            c.fill(Path(ellipseIn: CGRect(x: cx - 4.5, y: by - 4, width: 9, height: 10)), with: .color(Color(red: 0.12, green: 0.05, blue: 0.2)))
            c.fill(Path(ellipseIn: CGRect(x: cx - 3, y: by - 8, width: 6, height: 5)), with: .color(Color(red: 0.2, green: 0.08, blue: 0.3)))
            c.fill(Path(ellipseIn: CGRect(x: cx - 1.8, y: by - 1.5, width: 1.6, height: 1.6)), with: .color(.red))
            c.fill(Path(ellipseIn: CGRect(x: cx + 0.2, y: by - 1.5, width: 1.6, height: 1.6)), with: .color(.red))
        }
    }
}

/// Glowing carved pumpkin peeking up from the bottom-left corner.
struct JackOLantern: View {
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.orange.opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: 46))
                .frame(width: 96, height: 96)
            Ellipse().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.12), Color(red: 0.85, green: 0.38, blue: 0.02)], startPoint: .top, endPoint: .bottom))
                .frame(width: 54, height: 42)
            Ellipse().stroke(Color(red: 0.6, green: 0.25, blue: 0), lineWidth: 1.2).frame(width: 26, height: 42)
            Rectangle().fill(Color(red: 0.3, green: 0.45, blue: 0.2)).frame(width: 6, height: 9).offset(x: 2, y: -24)
            PumpkinFace().fill(Color(red: 1, green: 0.9, blue: 0.3)).frame(width: 36, height: 24).shadow(color: .yellow.opacity(0.8), radius: 3)
        }
        .frame(width: 58, height: 48)
    }
}

struct PumpkinFace: Shape {
    func path(in r: CGRect) -> Path {
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        for ex: CGFloat in [0.1, 0.62] { p.move(to: q(ex, 0.4)); p.addLine(to: q(ex + 0.28, 0.4)); p.addLine(to: q(ex + 0.14, 0)); p.closeSubpath() }
        p.move(to: q(0.02, 0.62))
        let xs: [CGFloat] = [0.14, 0.26, 0.38, 0.5, 0.62, 0.74, 0.86, 0.98]
        for (i, x) in xs.enumerated() { p.addLine(to: q(x, i % 2 == 0 ? 1 : 0.68)) }
        p.addLine(to: q(0.98, 0.62)); p.closeSubpath()
        return p
    }
}

struct SkullShape: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: 0.93, green: 0.9, blue: 0.8)).frame(width: 24, height: 20).offset(y: -2)
            RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.93, green: 0.9, blue: 0.8)).frame(width: 14, height: 8).offset(y: 8)
            HStack(spacing: 4) { Ellipse().frame(width: 6, height: 7); Ellipse().frame(width: 6, height: 7) }.foregroundStyle(Color(red: 0.1, green: 0.05, blue: 0.15)).offset(y: -2)
            Capsule().fill(Color(red: 0.1, green: 0.05, blue: 0.15)).frame(width: 3, height: 4).offset(y: 4)
        }
        .overlay(Ellipse().stroke(Color.black.opacity(0.3), lineWidth: 0.8).frame(width: 24, height: 20).offset(y: -2))
    }
}

/// Settings > Appearance: one compact row.
struct HalloweenSettingsRow: View {
    @AppStorage(Halloween.key) private var modeRaw = HalloweenMode.auto.rawValue

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Halloween mode").font(.caption)
                Text("Auto runs Oct 24 – Nov 1.").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Halloween mode", selection: $modeRaw) {
                ForEach(HalloweenMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 150)
        }
    }
}
