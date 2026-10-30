import Foundation

/// Optional plug-in point for a theme supplied outside this repository.
/// Every hook returns nil to keep the built-in default, so builds without a plug-in are unaffected.
protocol ThemeExtension: AnyObject {
    func outdoorLevel(_ theme: Theme) -> Double?
    func music(_ theme: Theme) -> MusicSpec?
    func raceMotif(_ theme: Theme) -> RaceOverlay.Motif?
    func raceLines(_ theme: Theme) -> (start: String, stumble: [String], win: [String])?
    func raceTitle(_ theme: Theme) -> String?
    func guestPool(_ theme: Theme) -> [GuestKind]?
    func guestQuip(_ theme: Theme) -> String?
    func mascotKind(_ theme: Theme) -> Mascot.Kind?
    func effectPalette(_ theme: Theme) -> [UInt32]?
    func levelTitles(_ themeRaw: String) -> [String]?
}

extension ThemeExtension {
    func outdoorLevel(_ theme: Theme) -> Double? { nil }
    func music(_ theme: Theme) -> MusicSpec? { nil }
    func raceMotif(_ theme: Theme) -> RaceOverlay.Motif? { nil }
    func raceLines(_ theme: Theme) -> (start: String, stumble: [String], win: [String])? { nil }
    func raceTitle(_ theme: Theme) -> String? { nil }
    func guestPool(_ theme: Theme) -> [GuestKind]? { nil }
    func guestQuip(_ theme: Theme) -> String? { nil }
    func mascotKind(_ theme: Theme) -> Mascot.Kind? { nil }
    func effectPalette(_ theme: Theme) -> [UInt32]? { nil }
    func levelTitles(_ themeRaw: String) -> [String]? { nil }
}

/// A plug-in registers by shipping an `NSObject` subclass exposed to the runtime as `HubbubThemeExtension`.
enum ThemeExtensions {
    nonisolated(unsafe) static let active: ThemeExtension? = {
        (NSClassFromString("HubbubThemeExtension") as? NSObject.Type)?.init() as? ThemeExtension
    }()
}
