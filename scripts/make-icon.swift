#!/usr/bin/env swift
// Renders the Hubbub app icon: a friendly headset bot at the centre of a busy hub,
// with little agent cubes orbiting it on an indigo -> magenta -> orange gradient.
// Usage (from repo root): swift scripts/make-icon.swift [--preview]
// Writes Resources/AppIcon.icns, Resources/NotificationIcon.png, docs/images/icon.png.
// With --preview also writes a contact sheet to scripts/.icon-preview/ (scratch; deleted by hand).
import AppKit
import CoreGraphics

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r / 255, g / 255, b / 255, a])!
}

/// Apple-style continuous-corner squircle (superellipse approximation).
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n = 5.0, steps = 240
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

func linear(_ ctx: CGContext, _ cols: [CGColor], _ locs: [CGFloat], from a: CGPoint, to b: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: cols as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ cols: [CGColor], _ locs: [CGFloat], at c: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: cols as CFArray, locations: locs)!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, in box: CGRect) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    linear(ctx, [top, bottom], [0, 1], from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY))
    ctx.restoreGState()
}

/// Draws one icon on a 1024-unit canvas scaled to `px` pixels. `small` drops fine detail.
func render(px: Int, small: Bool, bleed: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Body: 824pt squircle inside the 1024 canvas (Big Sur template). Small sizes use more of the canvas.
    let inset: CGFloat = small ? 40 : 100
    let body = CGRect(x: inset, y: inset, width: 1024 - 2 * inset, height: 1024 - 2 * inset)
    let bs = body.width / 824   // scale of all art relative to the 824 template
    ctx.saveGState()
    ctx.addPath(squircle(body)); ctx.clip()

    // Background gradient: deep indigo -> magenta -> orange glow at the bottom.
    linear(ctx, [rgb(38, 24, 110), rgb(104, 38, 150), rgb(214, 58, 140), rgb(255, 130, 70)], [0, 0.45, 0.8, 1],
           from: CGPoint(x: body.midX, y: body.maxY), to: CGPoint(x: body.midX, y: body.minY))
    radial(ctx, [rgb(255, 170, 90, 0.75), rgb(255, 120, 80, 0)], [0, 1],
           at: CGPoint(x: body.midX, y: body.minY + 120 * bs), radius: 520 * bs)
    if !small {
        // subtle gloss on the upper half
        ctx.saveGState()
        let gloss = CGMutablePath()
        gloss.addEllipse(in: CGRect(x: body.minX - 200 * bs, y: body.maxY - 330 * bs, width: body.width + 400 * bs, height: 700 * bs))
        ctx.addPath(gloss); ctx.clip()
        linear(ctx, [rgb(255, 255, 255, 0.20), rgb(255, 255, 255, 0.0)], [0, 1],
               from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.maxY - 330 * bs))
        ctx.restoreGState()
    }

    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: body.minX + x * bs, y: body.minY + y * bs) }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: body.minX + x * bs, y: body.minY + y * bs, width: w * bs, height: h * bs)
    }

    // Orbit ring (dashed ellipse tilted) – omitted when small.
    if !small {
        ctx.saveGState()
        ctx.translateBy(x: P(412, 400).x, y: P(412, 400).y)
        ctx.rotate(by: 0.0)
        ctx.setStrokeColor(rgb(255, 255, 255, 0.28)); ctx.setLineWidth(8 * bs)
        ctx.setLineDash(phase: 0, lengths: [2 * bs, 22 * bs]); ctx.setLineCap(.round)
        ctx.strokeEllipse(in: CGRect(x: -350 * bs, y: -255 * bs, width: 700 * bs, height: 510 * bs))
        ctx.restoreGState()
    }

    // Orbiting agent cubes (isometric-ish: top face lighter, left mid, right darker).
    func cube(_ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ top: CGColor, _ left: CGColor, _ right: CGColor) {
        let c = P(cx, cy), a = s * bs, h = a * 0.5
        let t = CGMutablePath()
        t.move(to: CGPoint(x: c.x, y: c.y + a)); t.addLine(to: CGPoint(x: c.x + a * 0.87, y: c.y + h))
        t.addLine(to: CGPoint(x: c.x, y: c.y)); t.addLine(to: CGPoint(x: c.x - a * 0.87, y: c.y + h)); t.closeSubpath()
        let l = CGMutablePath()
        l.move(to: CGPoint(x: c.x - a * 0.87, y: c.y + h)); l.addLine(to: CGPoint(x: c.x, y: c.y))
        l.addLine(to: CGPoint(x: c.x, y: c.y - a)); l.addLine(to: CGPoint(x: c.x - a * 0.87, y: c.y - h)); l.closeSubpath()
        let r = CGMutablePath()
        r.move(to: CGPoint(x: c.x, y: c.y)); r.addLine(to: CGPoint(x: c.x + a * 0.87, y: c.y + h))
        r.addLine(to: CGPoint(x: c.x + a * 0.87, y: c.y - h)); r.addLine(to: CGPoint(x: c.x, y: c.y - a)); r.closeSubpath()
        for (p, col) in [(l, left), (r, right), (t, top)] {
            ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath()
        }
        ctx.setLineJoin(.round); ctx.setStrokeColor(rgb(255, 255, 255, 0.35)); ctx.setLineWidth(3 * bs)
        for p in [t, l, r] { ctx.addPath(p); ctx.strokePath() }
    }
    let yellow = (rgb(255, 232, 130), rgb(255, 190, 60), rgb(240, 150, 40))
    let cyan = (rgb(150, 245, 235), rgb(60, 205, 215), rgb(40, 150, 195))
    let mint = (rgb(190, 255, 170), rgb(110, 220, 120), rgb(60, 170, 100))
    cube(small ? 130 : 120, small ? 640 : 610, small ? 62 : 52, yellow.0, yellow.1, yellow.2)
    cube(small ? 700 : 710, small ? 700 : 660, small ? 62 : 52, cyan.0, cyan.1, cyan.2)
    if !small { cube(660, 150, 40, mint.0, mint.1, mint.2) }
    if !small { cube(150, 190, 34, cyan.0, cyan.1, cyan.2) }

    // Bot: antenna
    let ax: CGFloat = 412
    ctx.setStrokeColor(rgb(255, 255, 255, 0.95)); ctx.setLineWidth(22 * bs); ctx.setLineCap(.round)
    ctx.move(to: P(ax, 560)); ctx.addLine(to: P(ax, small ? 650 : 640)); ctx.strokePath()
    let bulb = CGRect(x: P(ax, 0).x - 38 * bs, y: P(0, small ? 650 : 640).y - 4 * bs, width: 76 * bs, height: 76 * bs)
    ctx.saveGState(); ctx.addEllipse(in: bulb.insetBy(dx: -20 * bs, dy: -20 * bs)); ctx.clip()
    radial(ctx, [rgb(255, 210, 90, 0.55), rgb(255, 210, 90, 0)], [0, 1], at: CGPoint(x: bulb.midX, y: bulb.midY), radius: 58 * bs)
    ctx.restoreGState()
    ctx.addEllipse(in: bulb)
    ctx.saveGState(); ctx.clip()
    linear(ctx, [rgb(255, 245, 160), rgb(255, 160, 40)], [0, 1], from: CGPoint(x: bulb.midX, y: bulb.maxY), to: CGPoint(x: bulb.midX, y: bulb.minY))
    ctx.restoreGState()

    // Ear cups (headset)
    let earTop = rgb(255, 150, 90), earBot = rgb(235, 80, 120)
    for x: CGFloat in [118, 618] {
        let r = R(x, 250, 76, 150)
        fill(ctx, rounded(r, 34 * bs), top: earTop, bottom: earBot, in: r)
    }
    // Headband
    if !small {
        ctx.setStrokeColor(rgb(255, 255, 255, 0.9)); ctx.setLineWidth(18 * bs); ctx.setLineCap(.round)
        ctx.addArc(center: P(412, 330), radius: 285 * bs, startAngle: .pi * 0.9, endAngle: .pi * 0.1, clockwise: true)
        ctx.strokePath()
    }
    // Head
    let head = R(150, 200, 524, 370)
    let hp = rounded(head, 150 * bs)
    ctx.saveGState(); ctx.addPath(hp); ctx.clip()
    linear(ctx, [rgb(255, 255, 255), rgb(236, 226, 250), rgb(200, 186, 235)], [0, 0.6, 1],
           from: CGPoint(x: head.midX, y: head.maxY), to: CGPoint(x: head.midX, y: head.minY))
    if !small {
        radial(ctx, [rgb(255, 255, 255, 0.9), rgb(255, 255, 255, 0)], [0, 1], at: P(300, 520), radius: 220 * bs)
    }
    ctx.restoreGState()
    ctx.addPath(hp); ctx.setStrokeColor(rgb(120, 90, 190, 0.35)); ctx.setLineWidth(5 * bs); ctx.strokePath()

    // Visor
    let visor = R(205, 262, 414, 218)
    let vp = rounded(visor, 100 * bs)
    fill(ctx, vp, top: rgb(58, 34, 120), bottom: rgb(30, 18, 76), in: visor)
    if !small {
        ctx.saveGState(); ctx.addPath(vp); ctx.clip()
        linear(ctx, [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)], [0, 1],
               from: CGPoint(x: 0, y: visor.maxY), to: CGPoint(x: 0, y: visor.midY))
        ctx.restoreGState()
    }
    // Eyes (glowing cyan pills) + smile
    let eyeW: CGFloat = small ? 78 : 62, eyeH: CGFloat = small ? 112 : 96
    for x: CGFloat in [small ? 285 : 292, small ? 461 : 470] {
        let e = R(x, 330, eyeW, eyeH)
        if !small {
            ctx.saveGState(); ctx.addEllipse(in: e.insetBy(dx: -40 * bs, dy: -40 * bs)); ctx.clip()
            radial(ctx, [rgb(120, 255, 240, 0.45), rgb(120, 255, 240, 0)], [0, 1], at: CGPoint(x: e.midX, y: e.midY), radius: 90 * bs)
            ctx.restoreGState()
        }
        fill(ctx, rounded(e, eyeW / 2 * bs), top: rgb(190, 255, 250), bottom: rgb(70, 225, 225), in: e)
    }
    if !small {
        ctx.setStrokeColor(rgb(120, 255, 240)); ctx.setLineWidth(15 * bs); ctx.setLineCap(.round)
        ctx.move(to: P(372, 305)); ctx.addQuadCurve(to: P(452, 305), control: P(412, 270)); ctx.strokePath()
    }
    // Cheek blush
    if !small {
        ctx.setFillColor(rgb(255, 120, 170, 0.55))
        ctx.fillEllipse(in: R(175, 222, 40, 24)); ctx.fillEllipse(in: R(609, 222, 40, 24))
    }
    ctx.restoreGState()

    // Hairline inner edge for definition against light backgrounds
    ctx.addPath(squircle(body.insetBy(dx: 1, dy: 1)))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.18)); ctx.setLineWidth(small ? 1 : 3); ctx.strokePath()
    return ctx.makeImage()!
}

func writePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func resized(_ img: CGImage, _ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

let fm = FileManager.default
let root = fm.currentDirectoryPath
guard fm.fileExists(atPath: root + "/build-app.sh") else { print("run from the repo root"); exit(1) }
let work = root + "/scripts/.icon-work"
let iconset = work + "/AppIcon.iconset"
try? fm.removeItem(atPath: work)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Sizes up to 64px use the simplified art; larger ones the full art (rendered natively per size).
var cache: [Int: CGImage] = [:]
func icon(_ px: Int) -> CGImage {
    if let c = cache[px] { return c }
    let img = px >= 1024 ? render(px: px, small: false) : (px >= 128 ? resized(render(px: 1024, small: false), px) : render(px: px * 4, small: px <= 64).downscaled(px))
    cache[px] = img
    return img
}
extension CGImage { func downscaled(_ px: Int) -> CGImage { resized(self, px) } }

let names: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (n, px) in names { writePNG(icon(px), "\(iconset)/\(n).png") }

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", root + "/Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
guard p.terminationStatus == 0 else { print("iconutil failed"); exit(1) }

writePNG(icon(1024), work + "/master.png")
writePNG(icon(256), root + "/Resources/NotificationIcon.png")
try? fm.createDirectory(atPath: root + "/docs/images", withIntermediateDirectories: true)
writePNG(icon(256), root + "/docs/images/icon.png")

if CommandLine.arguments.contains("--preview") {
    // Contact sheet: 16, 32, 64, 128, 256, 512 on light and dark strips.
    let sizes = [16, 32, 64, 128, 256, 512]
    let W = 1300, H = 1200
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, bg) in [rgb(245, 245, 247), rgb(30, 30, 34)].enumerated() {
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: row * 600, width: W, height: 600))
        var x = 20
        for s in sizes where s <= 256 { ctx.draw(icon(s), in: CGRect(x: x, y: row * 600 + 320, width: s, height: s)); x += s + 20 }
        ctx.draw(icon(512), in: CGRect(x: 20, y: row * 600 + 20, width: 280, height: 280))
        ctx.draw(icon(16), in: CGRect(x: 340, y: row * 600 + 100, width: 160, height: 160))
    }
    writePNG(ctx.makeImage()!, work + "/sheet.png")
} else {
    // keep only the master for inspection when asked via --preview
    try? fm.removeItem(atPath: work)
}
print("Icon regenerated.")
