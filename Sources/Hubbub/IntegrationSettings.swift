import SwiftUI

/// Settings cards for Focus / quiet hours and the end-of-day summary (Alerts tab).
struct FocusSettingsView: View {
    @ObservedObject private var guardian = FocusGuard.shared
    @AppStorage(FocusGuard.Key.respectFocus) private var respectFocus = true
    @AppStorage(FocusGuard.Key.quietEnabled) private var quiet = false
    @AppStorage(FocusGuard.Key.quietStart) private var start = 22 * 60
    @AppStorage(FocusGuard.Key.quietEnd) private var end = 7 * 60
    @State private var authorized = FocusGuard.shared.focusAuthorized

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Hold during macOS Focus", isOn: $respectFocus).onChange(of: respectFocus) { _ in guardian.evaluate() }
            if respectFocus && !authorized {
                HStack {
                    Text("Needs permission to read your Focus status.").font(.caption2).foregroundStyle(.secondary)
                    Button("Allow") { FocusGuard.shared.requestFocusAccess { authorized = FocusGuard.shared.focusAuthorized } }.controlSize(.small)
                }
            }
            Toggle("Quiet hours", isOn: $quiet).onChange(of: quiet) { _ in guardian.evaluate() }
            if quiet {
                HStack {
                    TimeMinutePicker(title: "From", minutes: $start)
                    TimeMinutePicker(title: "to", minutes: $end)
                    Spacer(minLength: 0)
                }
            }
            Text(guardian.heldCount > 0 ? "\(guardian.heldCount) held; a summary arrives when it ends."
                 : "Held alerts arrive as one summary afterwards.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { authorized = FocusGuard.shared.focusAuthorized }
        .onChange(of: start) { _ in guardian.evaluate() }
        .onChange(of: end) { _ in guardian.evaluate() }
    }
}

struct DailySummarySettingsView: View {
    @AppStorage(IntegrationHub.Key.summaryEnabled) private var on = false
    @AppStorage(IntegrationHub.Key.summaryMinute) private var minute = 18 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Daily summary notification", isOn: $on)
            if on { TimeMinutePicker(title: "At", minutes: $minute) }
            HStack {
                Text("Sessions, failures and tokens. Opens Insights.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Send now") { IntegrationHub.shared.sendSummaryNow() }.controlSize(.small)
            }
        }
    }
}

struct HudSettingsView: View {
    @AppStorage(HudController.enabledKey) private var on = false
    @AppStorage(HudController.clickThroughKey) private var clickThrough = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Show floating mini HUD", isOn: $on).onChange(of: on) { _ in HudController.shared.apply() }
            Toggle("Click-through (can't be dragged)", isOn: $clickThrough)
                .disabled(!on).onChange(of: clickThrough) { _ in HudController.shared.apply() }
            Text("Floating status: quota, agents and state. Drag to move.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct TimeMinutePicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { minutes = QuietHours.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
            .datePickerStyle(.compact).fixedSize()
    }
}
