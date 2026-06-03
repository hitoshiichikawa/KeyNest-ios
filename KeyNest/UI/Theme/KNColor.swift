import SwiftUI
import UIKit

/// KeyNest semantic color tokens, light + dark.
///
/// Mirrors `app/src/main/res/values{,-night}/colors.xml` in the Android port.
/// Only the semantic layer (`kn_bg`, `kn_text`, `kn_primary`, …) is exposed —
/// raw palette steps stay implementation details. Light values resolve the
/// XML aliases (e.g. `kn_paper` → `#F6F8FC`) so the iOS app does not have
/// to ship the full palette.
///
/// We use `UIColor(dynamicProvider:)` rather than an asset catalog so the
/// whole token set stays text-reviewable in one file.
enum KNColor {
    static let bg                  = dynamic(light: 0xF6F8FC, dark: 0x0A1020)
    static let bgElev              = dynamic(light: 0xFFFFFF, dark: 0x0F1729)
    static let surface             = dynamic(light: 0xFFFFFF, dark: 0x131C33)
    static let surface2            = dynamic(light: 0xF1F4FA, dark: 0x1A2540)
    static let surfaceTint         = dynamic(light: rgba(0xEAF2FE, 1), dark: rgba(0x1F6FEB, 0x29 / 255.0))

    static let border              = dynamic(light: rgba(0x000000, 0x14 / 255.0), dark: rgba(0xFFFFFF, 0x0F / 255.0))
    static let borderStrong        = dynamic(light: rgba(0x000000, 0x24 / 255.0), dark: rgba(0xFFFFFF, 0x1F / 255.0))

    static let text                = dynamic(light: 0x0B1220, dark: 0xECF1FA)
    static let text2               = dynamic(light: 0x5C6B8E, dark: 0x9CA9C7)
    static let text3               = dynamic(light: 0x7A89AD, dark: 0x7A89AD)

    static let primary             = dynamic(light: 0x1F6FEB, dark: 0x4D8DF4)
    static let primaryHover        = dynamic(light: 0x1457C9, dark: 0x6FA1F2)
    static let onPrimary           = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let primaryContainer    = dynamic(light: 0xEAF2FE, dark: 0x1A2D5C)
    static let onPrimaryContainer  = dynamic(light: 0x0A2E66, dark: 0xD0E0FC)

    // Status — base hexes are shared with Android; *Soft variants dim on dark.
    static let success             = staticColor(0x10B981)
    static let successSoft         = dynamic(light: rgba(0xD1FAE5, 1), dark: rgba(0x10B981, 0x1F / 255.0))
    static let warning             = staticColor(0xF59E0B)
    static let warningSoft         = dynamic(light: rgba(0xFEF3C7, 1), dark: rgba(0xF59E0B, 0x1F / 255.0))
    static let danger              = staticColor(0xEF4444)
    static let dangerSoft          = dynamic(light: rgba(0xFEE2E2, 1), dark: rgba(0xEF4444, 0x1F / 255.0))
    static let info                = staticColor(0x38BDF8)

    // MARK: - Helpers

    private struct RGBA { let r, g, b, a: CGFloat }

    private static func rgba(_ hex: Int, _ alpha: CGFloat) -> RGBA {
        RGBA(
            r: CGFloat((hex >> 16) & 0xFF) / 255.0,
            g: CGFloat((hex >> 8) & 0xFF) / 255.0,
            b: CGFloat(hex & 0xFF) / 255.0,
            a: alpha
        )
    }

    private static func dynamic(light: Int, dark: Int) -> Color {
        dynamic(light: rgba(light, 1), dark: rgba(dark, 1))
    }

    private static func dynamic(light: RGBA, dark: RGBA) -> Color {
        Color(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }

    private static func staticColor(_ hex: Int) -> Color {
        let c = rgba(hex, 1)
        return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }
}
