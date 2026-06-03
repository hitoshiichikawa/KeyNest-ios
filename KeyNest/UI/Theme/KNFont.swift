import SwiftUI

/// KeyNest typography. Manrope is the primary face (Req 8.2), JetBrains Mono
/// the monospace face used for secrets / hex / signature chips.
///
/// The TTFs ship under `KeyNest/Resources/Fonts/` and are registered in
/// `Info.plist` `UIAppFonts`. PostScript names match the file names so we
/// reference them directly with `Font.custom(_:size:)`.
enum KNFont {
    enum Weight {
        case regular, medium, semibold, bold

        var postScriptName: String {
            switch self {
            case .regular:  return "Manrope-Regular"
            case .medium:   return "Manrope-Medium"
            case .semibold: return "Manrope-SemiBold"
            case .bold:     return "Manrope-Bold"
            }
        }
    }

    /// Manrope at the given size + weight, scaled by Dynamic Type via
    /// `relativeTo`.
    static func sans(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom(weight.postScriptName, size: size, relativeTo: style)
    }

    /// JetBrains Mono Regular — used for ciphertext, hashes, signature chips.
    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        Font.custom("JetBrainsMono-Regular", size: size, relativeTo: style)
    }

    // Convenience aliases roughly matching the Android type-scale.
    static let title    = sans(28, .bold,     relativeTo: .title)
    static let title2   = sans(22, .semibold, relativeTo: .title2)
    static let title3   = sans(18, .semibold, relativeTo: .title3)
    static let headline = sans(16, .semibold, relativeTo: .headline)
    static let body     = sans(16, .regular,  relativeTo: .body)
    static let callout  = sans(15, .medium,   relativeTo: .callout)
    static let caption  = sans(13, .regular,  relativeTo: .caption)
    static let footnote = sans(12, .medium,   relativeTo: .footnote)
}
