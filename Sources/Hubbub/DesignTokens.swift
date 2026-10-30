import SwiftUI

/// Type scale: four styles only, nothing below 11 pt.
enum HubFont {
    static let metric = Font.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit()
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let bodyDigits = Font.system(size: 12).monospacedDigit()
    static let captionDigits = Font.system(size: 11).monospacedDigit()
}

/// 4 pt spacing grid, shape constants.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let radius: CGFloat = 10
    static let bar: CGFloat = 6
    static let row: CGFloat = 28
}

enum Level: Equatable { case ok, warn, alert }

/// Colour semantics: fractions are 0…1; colour belongs on bars/dots, numbers stay primary.
enum Semantic {
    static func context(_ f: Double) -> Level { f >= 0.85 ? .alert : f >= 0.60 ? .warn : .ok }
    static func quota(_ f: Double) -> Level { f >= 0.90 ? .alert : f >= 0.70 ? .warn : .ok }
    static func budget(_ f: Double) -> Level { f >= 1.0 ? .alert : f >= 0.80 ? .warn : .ok }

    static func color(_ l: Level) -> Color { l == .ok ? .green : l == .warn ? .orange : .red }

    /// Spoken suffix so colour is never the only signal.
    static func spoken(_ l: Level) -> String { l == .ok ? "" : l == .warn ? "getting full" : "critical" }

    /// Glyph for amber/red sub-lines.
    static func glyph(_ l: Level) -> String { l == .ok ? "" : "⚠︎" }
}
