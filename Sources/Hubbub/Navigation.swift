import SwiftUI

/// Single navigation state for the popover.
enum Screen: Hashable {
    case live, history, insights, achievements
    case detail(String)
    case settings

    var isTab: Bool {
        switch self { case .live, .history, .insights, .achievements: true; default: false }
    }
}

/// Navigation actions injected into the ContentView hierarchy (`@Environment(\.hubbubNav)`).
/// Child views (Detail, info panel) call these instead of keeping their own back stacks.
struct HubbubNav {
    var openDetail: () -> Void = {}
    var back: () -> Void = {}
    var refreshQuota: () -> Void = {}
    /// Opens Settings, optionally on a tab ("providers", "advanced", …).
    var openSettings: (String?) -> Void = { _ in }
}

private struct HubbubNavKey: EnvironmentKey { static let defaultValue = HubbubNav() }
extension EnvironmentValues {
    var hubbubNav: HubbubNav {
        get { self[HubbubNavKey.self] }
        set { self[HubbubNavKey.self] = newValue }
    }
}
