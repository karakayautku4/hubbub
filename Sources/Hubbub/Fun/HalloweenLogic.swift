import Foundation

/// Settings > Appearance > Halloween: Auto follows the calendar, On/Off force it.
enum HalloweenMode: String, CaseIterable, Identifiable {
    case auto, on, off
    var id: String { rawValue }
    var title: String { switch self { case .auto: "Auto"; case .on: "On"; case .off: "Off" } }
}

/// Pure decision logic for the seasonal mode (shared by the 3D overlay, the UI chrome and `--selftest-halloween`).
enum Halloween {
    static let key = "halloweenMode"
    /// Debug override: HUBBUB_HALLOWEEN=1 forces the mode on, =0 forces it off (beats the setting).
    static let envKey = "HUBBUB_HALLOWEEN"

    /// Oct 24 … Nov 1, inclusive.
    static func inWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return false }
        return (m == 10 && d >= 24) || (m == 11 && d == 1)
    }

    static func isActive(mode: HalloweenMode, date: Date = Date(), calendar: Calendar = .current, env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        switch env[envKey]?.lowercased() {
        case "1", "true", "on", "yes": return true
        case "0", "false", "off", "no": return false
        default: break
        }
        switch mode {
        case .on: return true
        case .off: return false
        case .auto: return inWindow(date, calendar: calendar)
        }
    }

    static func mode(from raw: String?) -> HalloweenMode { raw.flatMap(HalloweenMode.init(rawValue:)) ?? .auto }

    static var storedMode: HalloweenMode { mode(from: UserDefaults.standard.string(forKey: key)) }
    static var isActiveNow: Bool { isActive(mode: storedMode) }
}
