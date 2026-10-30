import SwiftUI
import AppKit

/// `--snapshot-screen insights|history|achievements|details <out.png> [width]`: renders a data screen offscreen.
enum DataScreensSnapshot {
    @MainActor static func run(_ args: [String]) {
        guard args.count >= 2 else { print("usage: --snapshot-screen insights|history|achievements|details out.png [width]"); return }
        let width = args.count > 2 ? Double(args[2]) ?? 440 : 440
        let monitor = SessionMonitor(); monitor.start()
        let root: AnyView
        switch args[0] {
        case "insights": root = AnyView(InsightsView(monitor: monitor))
        case "history": root = AnyView(HistoryView())
        case "achievements": root = AnyView(AchievementsView())
        default:
            let rec = SessionLibrary.shared.records.first ?? SessionRecord(id: "demo", provider: "copilot", name: "Demo", lastEvent: Date())
            root = AnyView(SessionDetailView(record: rec) {})
        }
        let host = NSHostingView(rootView: root.frame(width: width - 24).padding(12))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[1]))
        }
        print("\(args[0]) @\(Int(width))pt: size \(host.fittingSize)")
    }
}
