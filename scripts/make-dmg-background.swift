#!/usr/bin/env swift
// Renders the DMG window background (660x400 px) for make-dmg.sh.
// Usage: swift scripts/make-dmg-background.swift <out.png>
import AppKit
import CoreGraphics

let W = 660, H = 400
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}
guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsctx

// Soft light background so Finder's dark icon labels stay readable in both appearances.
let grad = CGGradient(colorsSpace: cs, colors: [rgb(250, 248, 255), rgb(233, 228, 250)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
    (s as NSString).draw(in: CGRect(x: centerX - 320, y: y, width: 640, height: size * 1.4), withAttributes: a)
}

// Title row with the app icon (icon.png is optional; skipped if missing).
let iconPath = "Resources/AppIcon.icns"
if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: CGRect(x: 245, y: 335, width: 40, height: 40))
}
text("Hubbub", size: 26, weight: .bold, color: NSColor(calibratedRed: 0.25, green: 0.2, blue: 0.5, alpha: 1), centerX: 345, y: 337)

// Arrow between the two icon slots (app at x=180, Applications at x=480; icon centres at y=190 from the top).
let cy = CGFloat(H) - 190
ctx.setStrokeColor(rgb(124, 92, 220)); ctx.setFillColor(rgb(124, 92, 220))
ctx.setLineWidth(8); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 265, y: cy)); ctx.addLine(to: CGPoint(x: 375, y: cy)); ctx.strokePath()
ctx.move(to: CGPoint(x: 395, y: cy)); ctx.addLine(to: CGPoint(x: 365, y: cy + 24)); ctx.addLine(to: CGPoint(x: 365, y: cy - 24)); ctx.closePath(); ctx.fillPath()

text("Drag Hubbub to Applications", size: 18, weight: .semibold, color: NSColor(calibratedWhite: 0.2, alpha: 1), centerX: 330, y: 95)
text("macOS says it can’t verify the app? Right-click Hubbub → Open. See “Read Me First.html”.", size: 12, weight: .regular,
     color: NSColor(calibratedWhite: 0.38, alpha: 1), centerX: 330, y: 30)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
