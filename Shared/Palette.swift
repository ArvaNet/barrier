import BarrierCore
import SwiftUI
import UIKit

// Tendwell's look, two layers: emerald for trust (the brand, the night stage, links),
// marigold for joy (the one main action on a screen). Day is a cool mineral porcelain;
// Dusk is the night ritual. Cycle hues always mean their night.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }
}

enum Palette {
    static let bg = Color(uiColor: .dynamic(light: 0xEDF0ED, dark: 0x0B1612))
    /// Cards and list rows: one surface for both, so every tab is one app.
    static let surface = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0x12221C))
    static let surface2 = Color(uiColor: .dynamic(light: 0xE3E8E4, dark: 0x1A2E26))
    static let surface3 = Color(uiColor: .dynamic(light: 0xD6DDD8, dark: 0x233A31))
    /// Button and chip fills. Translucent at dusk so they read on any card, the stage included.
    static let fill = Color(uiColor: .dynamic(light: 0xE3E8E4, dark: 0xECE7DE, darkAlpha: 0.1))
    static let ink = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE))
    static let ink2 = Color(uiColor: .dynamic(light: 0x485853, dark: 0xA9B2AD))
    /// Tertiary text: 5:1 even on surface2 in light mode.
    static let ink3 = Color(uiColor: .dynamic(light: 0x56635E, dark: 0x85908B))
    static let line = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE, lightAlpha: 0.12, darkAlpha: 0.1))
    static let line2 = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE, lightAlpha: 0.22, darkAlpha: 0.18))
    /// Emerald, for actions written as text or icons (Add a product, Save) and for marks.
    /// 5.3:1 on white by day; mint at dusk.
    static let accent = Color(uiColor: .dynamic(light: 0x1F7A52, dark: 0x7FD8A8))
    static let accentSoft = Color(uiColor: .dynamic(light: 0x1F7A52, dark: 0x7FD8A8, lightAlpha: 0.1, darkAlpha: 0.16))
    /// Marigold: the one main button on a screen, in both themes. Its label is `onCta`.
    static let cta = Color(hex: 0xF5B83D)
    static let onCta = Color(hex: 0x33240A)
    /// The brand's deep emerald (the icon, the welcome) and its mint rings.
    static let brand = Color(hex: 0x0E4D35)
    static let brandMint = Color(hex: 0x7FD8A8)
    static let marigold = Color(hex: 0xF5B83D)
    /// Selection: an ink outline, never a clay wash.
    static let selected = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE, lightAlpha: 0.06, darkAlpha: 0.08))
    static let warnSoft = Color(uiColor: .dynamic(light: 0xC99A3C, dark: 0xE8C87A, lightAlpha: 0.15, darkAlpha: 0.12))
    static let warn = Color(uiColor: .dynamic(light: 0x8A5F10, dark: 0xE3BD6A))
    static let danger = Color(uiColor: .dynamic(light: 0xA4402F, dark: 0xE08A78))
    static let ok = Color(uiColor: .dynamic(light: 0x4F7A4E, dark: 0x9DB89C))

    /// The night stage: deep emerald, in both themes.
    static let stage = Color(hex: 0x0F3B2B)
    static let stage2 = Color(hex: 0x164A37)
    /// The Tonight card: the stage by day; one step lighter than the cards at dusk, so it leads.
    static let stageCard = Color(uiColor: .dynamic(light: 0x0F3B2B, dark: 0x164A37))
    static let stageInk = Color(hex: 0xECE7DE)
    static let stageInk2 = Color(hex: 0xA9B2AD)
    static let stageLine = Color(hex: 0xECE7DE, alpha: 0.12)
    static let stageAccent = Color(hex: 0xF5B83D)

    static func hue(_ h: Hue?) -> Color {
        switch h ?? .sage {
        case .gold: return Color(hex: 0xE8C87A)
        case .clay: return Color(hex: 0xD97E5A)
        case .sage: return Color(hex: 0x9DB89C)
        case .mist: return Color(hex: 0xA8C0C8)
        case .rose: return Color(hex: 0xD7A1AE)
        case .lilac: return Color(hex: 0xB9A8D6)
        case .dawn: return Color(hex: 0xF0B98D)
        }
    }

    /// Hue text that stays readable on light surfaces.
    static func hueInk(_ h: Hue?) -> Color {
        switch h ?? .sage {
        case .gold: return Color(uiColor: .dynamic(light: 0x8A6A1C, dark: 0xE8C87A))
        case .clay: return Color(uiColor: .dynamic(light: 0xA6512E, dark: 0xD97E5A))
        case .sage: return Color(uiColor: .dynamic(light: 0x4F7A4E, dark: 0x9DB89C))
        case .mist: return Color(uiColor: .dynamic(light: 0x47707C, dark: 0xA8C0C8))
        case .rose: return Color(uiColor: .dynamic(light: 0x9A4F62, dark: 0xD7A1AE))
        case .lilac: return Color(uiColor: .dynamic(light: 0x6B5A93, dark: 0xB9A8D6))
        case .dawn: return Color(uiColor: .dynamic(light: 0x9C5A2A, dark: 0xF0B98D))
        }
    }
}

extension Hue {
    var color: Color { Palette.hue(self) }
}

// MARK: - Type

enum Typeface {
    private static let wght: Int = 0x7767_6874 // 'wght'
    private static let opsz: Int = 0x6F70_737A // 'opsz'
    private static let soft: Int = 0x534F_4654 // 'SOFT'

    /// Fraunces with explicit axes; falls back to New York if the font isn't loaded.
    static func display(_ size: CGFloat, weight: CGFloat = 420, relativeTo style: UIFont.TextStyle = .largeTitle) -> Font {
        let font = uiDisplay(size, weight: weight, relativeTo: style)
        return Font(font as CTFont)
    }

    /// The same, as a UIFont (navigation bars, attributed text).
    static func uiDisplay(_ size: CGFloat, weight: CGFloat = 420, relativeTo style: UIFont.TextStyle = .largeTitle) -> UIFont {
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        let attrs: [UIFontDescriptor.AttributeName: Any] = [
            .family: "Fraunces",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                wght: weight, opsz: min(144, max(9, size)), soft: 60,
            ],
        ]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: scaled)
        if font.familyName.lowercased().contains("fraunces") { return font }
        let serif = UIFont.systemFont(ofSize: scaled, weight: .regular).fontDescriptor.withDesign(.serif)
        return serif.map { UIFont(descriptor: $0, size: scaled) } ?? .systemFont(ofSize: scaled)
    }

    /// Every tab's large title in Fraunces, the inline title in SF: native behavior, brand voice.
    static func styleNavigationBars() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: uiDisplay(34, weight: 430),
            .foregroundColor: UIColor.dynamic(light: 0x1B2A26, dark: 0xECE7DE),
            // Large type wants slightly tighter tracking.
            .kern: -0.5,
        ]
    }
}

extension Font {
    /// The hero card's title: one line for "Recovery night" at the default size.
    static let barrierDisplay = Typeface.display(30, weight: 430)
    /// Big numbers only: the timer, the Progress count.
    static let barrierNumeral = Typeface.display(56, weight: 380)
    /// Page titles: the navigation bar, onboarding, the guided routine.
    static let barrierLargeTitle = Typeface.display(34, weight: 430)
    static let barrierH2 = Typeface.display(22, weight: 480, relativeTo: .title2)
    static let barrierH3 = Typeface.display(19, weight: 500, relativeTo: .title3)
}

// MARK: - Theme

extension ThemeMode {
    /// The color scheme to force, or nil to follow the iPhone.
    func scheme(at date: Date = Date(), calendar: Calendar = .current) -> ColorScheme? {
        switch self {
        case .system: return nil
        case .day: return .light
        case .dusk: return .dark
        case .timeOfDay:
            let h = calendar.component(.hour, from: date)
            return (h >= 18 || h < 6) ? .dark : .light
        }
    }
}
