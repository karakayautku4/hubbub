import SwiftUI

@main
struct HubbubApp: App {
    init() {
        if CommandLine.arguments.contains("--reply-hook") { ReplyHookClient.main(arguments: CommandLine.arguments) }
        NSApplication.shared.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            AppRouter.shared.openPopoverHandler = { HotkeyManager.openPopover() }
            MenuBarController.shared.install()
            HotkeyManager.shared.start()
            Notifier.shared.activate()
            ReplyCenter.shared.applySettings()
        }
        if CommandLine.arguments.contains("--selftest") { Snapshot.selfTest(); exit(0) }
        if CommandLine.arguments.contains("--selftest-notifications") { exit(NotificationSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-reply") { exit(MainActor.assumeIsolated { ReplySelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-update") { exit(UpdateChecker.selfTest() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-budget") { exit(BudgetSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-screen") { MainActor.assumeIsolated { DataScreensSnapshot.run(Array(CommandLine.arguments[(i + 1)...])) }; exit(0) }
        if CommandLine.arguments.contains("--selftest-fmt") { exit(FormatSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-themes") { exit(ThemeSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-export") { exit(MainActor.assumeIsolated { SessionExport.selfTest() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-fx") { exit(MainActor.assumeIsolated { FXTools.selfTest() } ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--fxshot"), i + 3 < CommandLine.arguments.count {
            MainActor.assumeIsolated { FXTools.shot(theme: CommandLine.arguments[i + 1], path: CommandLine.arguments[i + 2], seconds: Double(CommandLine.arguments[i + 3]) ?? 3) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--perf-data-gen") { PerfDataSelfTest.generateMain(Array(CommandLine.arguments[(i + 1)...])); exit(0) }
        if CommandLine.arguments.contains("--selftest-perf-data") { exit(PerfDataSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--perf-data-real"), i + 1 < CommandLine.arguments.count {
            PerfDataSelfTest.runReal(CommandLine.arguments[i + 1]); exit(0)
        }
        if CommandLine.arguments.contains("--selftest-quota") { exit(QuotaSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-a11y") { exit(MainActor.assumeIsolated { A11ySelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-perf") { exit(MainActor.assumeIsolated { PerfSelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-jobs") { exit(MainActor.assumeIsolated { JobsSelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-ui") { exit(MainActor.assumeIsolated { UISelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-integration") { exit(IntegrationSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--status") { StatusFormat.runCLI(json: CommandLine.arguments.contains("--json")) }
        MainActor.assumeIsolated { IntegrationHub.shared.installURLHandler() }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-halloween") { MainActor.assumeIsolated { HalloweenSnapshot.run(Array(CommandLine.arguments[(i + 1)...])) }; exit(0) }
        if CommandLine.arguments.contains("--selftest-halloween") { exit(MainActor.assumeIsolated { HalloweenSelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-fun") { exit(MainActor.assumeIsolated { FunSelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-providers") { exit(ProviderSelfTest.run() ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-prodfeatures") { exit(MainActor.assumeIsolated { ProdFeaturesSelfTest.run() } ? 0 : 1) }
        if CommandLine.arguments.contains("--selftest-settings") { exit(MainActor.assumeIsolated { SettingsSelfTest.run() } ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-settings") { MainActor.assumeIsolated { SettingsSnapshot.run(Array(CommandLine.arguments[(i + 1)...])) }; exit(0) }
        if CommandLine.arguments.contains("--selftest-progress") { exit(ProgressSelfTest.run() ? 0 : 1) }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-ui"), i + 1 < CommandLine.arguments.count {
            Snapshot.renderUI(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.render(to: CommandLine.arguments[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        // The menu bar item, popover and expanded window are owned by MenuBarController / SurfaceController;
        // this never-inserted scene only keeps SwiftUI's app lifecycle (and standard Edit menu) without opening any window.
        MenuBarExtra("Hubbub", isInserted: .constant(false)) { EmptyView() }
    }
}
