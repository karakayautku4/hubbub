import SwiftUI
import Combine

/// Single source of truth shared by the menu bar popover and the expanded window.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let monitor = SessionMonitor()
    let quota = QuotaService()
    let budget = BudgetCenter.shared
    let stage = Stage()

    @Published var screen: Screen = .live
    @Published var selectedID: String?

    private var bag = Set<AnyCancellable>()
    private var started = false

    /// Starts the background services once; safe to call repeatedly.
    func start() {
        guard !started else { return }
        started = true
        monitor.start()
        quota.start()
        ProviderQuotaService.shared.start()
        IntegrationHub.shared.attach(monitor: monitor, quota: quota)
        monitor.$sessions.dropFirst().sink { s in
            Notifier.shared.sessions(s); BudgetCenter.shared.update(s); ReplyCenter.shared.observe(s)
        }.store(in: &bag)
        quota.$quota.dropFirst().sink { Notifier.shared.quota($0) }.store(in: &bag)
    }
}
