import Foundation
import SwiftUI

/// Fictional clubs with generic kit colours, used by the football theme. Any resemblance to real clubs is coincidental.
enum Team: String, CaseIterable, Identifiable {
    case crimsonFoxes, sunflowerRovers, inkMagpies, bayviewGulls, cobaltHerons, ivoryStags, emberRangers, skyOtters, scarletWolves, canaryCoast
    var id: String { rawValue }

    static let fallback: Team = .crimsonFoxes
    /// Unknown stored values (e.g. from older versions) fall back to the default club.
    static func from(_ raw: String) -> Team { Team(rawValue: raw) ?? fallback }
    static var current: Team { from(UserDefaults.standard.string(forKey: "team") ?? "") }

    var name: String {
        switch self {
        case .crimsonFoxes: "Crimson Foxes"
        case .sunflowerRovers: "Sunflower Rovers"
        case .inkMagpies: "Ink Magpies"
        case .bayviewGulls: "Bayview Gulls"
        case .cobaltHerons: "Cobalt Herons"
        case .ivoryStags: "Ivory Stags"
        case .emberRangers: "Ember Rangers"
        case .skyOtters: "Sky Otters"
        case .scarletWolves: "Scarlet Wolves"
        case .canaryCoast: "Canary Coast"
        }
    }
    /// shirt, shorts, trim (hex)
    var kit: (UInt32, UInt32, UInt32) {
        switch self {
        case .crimsonFoxes: (0xb5173c, 0xf2b01e, 0xf2b01e)
        case .sunflowerRovers: (0xf7e11a, 0x1d3f8a, 0x1d3f8a)
        case .inkMagpies: (0x1a1a1a, 0xf4f4f4, 0xf4f4f4)
        case .bayviewGulls: (0x7d2a4a, 0x39a6d8, 0x39a6d8)
        case .cobaltHerons: (0x1f4fa8, 0x8f1f45, 0xe6b422)
        case .ivoryStags: (0xf6f3ea, 0xf6f3ea, 0xd9a520)
        case .emberRangers: (0xd23a28, 0xd23a28, 0xf4f4f4)
        case .skyOtters: (0x8ec3ea, 0xf4f4f4, 0x24386b)
        case .scarletWolves: (0xd8203a, 0xf4f4f4, 0x2b6fc0)
        case .canaryCoast: (0xf3d916, 0x1c56a8, 0x2e9a50)
        }
    }
    var shirt: Color { Color(hex: kit.0) }
    var trim: Color { Color(hex: kit.2) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
