import Foundation

/// Shared entry point for "go to this session" requests (notifications, hotkey, deep links).
/// Notifier calls `open(sessionID:)`; ContentView observes `pendingSessionID`; App.swift/Hotkey wire `openPopoverHandler`.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    /// Session the UI should select and show in Detail; ContentView clears it after consuming.
    @Published var pendingSessionID: String?
    /// Installed by the menu bar layer; opens/focuses the popover window.
    var openPopoverHandler: (() -> Void)?
    /// Top-level screen to show ("live", "history", "insights", "settings"); ContentView clears it after consuming.
    @Published var pendingScreen: String?

    func open(screen: String) {
        pendingScreen = screen
        openPopoverHandler?()
    }

    func open(sessionID: String?) {
        pendingSessionID = sessionID
        openPopoverHandler?()
    }
}
