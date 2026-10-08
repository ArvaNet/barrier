import BarrierCore
import SwiftUI
import UIKit

// Barrier's look: dermatological calm. Day is a cool mineral porcelain for
// mornings; Dusk is the night ritual. Cycle hues always mean their night.

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
    static let bg = Color(uiColor: .dynamic(light: 0xEDF0ED, dark: 0x0E1513))
    static let surface = Color(uiColor: .dynamic(light: 0xFAFBFA, dark: 0x16211E))
    static let surface2 = Color(uiColor: .dynamic(light: 0xE3E8E4, dark: 0x1E2B27))
    static let surface3 = Color(uiColor: .dynamic(light: 0xD6DDD8, dark: 0x283733))
    static let ink = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE))
    static let ink2 = Color(uiColor: .dynamic(light: 0x485853, dark: 0xA9B2AD))
    static let ink3 = Color(uiColor: .dynamic(light: 0x63706B, dark: 0x85908B))
    static let line = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE, lightAlpha: 0.12, darkAlpha: 0.1))
    static let line2 = Color(uiColor: .dynamic(light: 0x1B2A26, dark: 0xECE7DE, lightAlpha: 0.22, darkAlpha: 0.18))
    static let accent = Color(uiColor: .dynamic(light: 0xA6512E, dark: 0xC2673F))
    static let accentSoft = Color(uiColor: .dynamic(light: 0xA6512E, dark: 0xC2673F, lightAlpha: 0.1, darkAlpha: 0.18))
    static let warnSoft = Color(uiColor: .dynamic(light: 0xC99A3C, dark: 0xE8C87A, lightAlpha: 0.15, darkAlpha: 0.12))
    static let warn = Color(uiColor: .dynamic(light: 0x8A5F10, dark: 0xE3BD6A))
    static let danger = Color(uiColor: .dynamic(light: 0xA4402F, dark: 0xE08A78))
    static let ok = Color(uiColor: .dynamic(light: 0x4F7A4E, dark: 0x9DB89C))

    /// The night stage: always dusk, in both themes.
    static let stage = Color(hex: 0x131D1A)
    static let stage2 = Color(hex: 0x1B2824)
    static let stageInk = Color(hex: 0xECE7DE)
    static let stageInk2 = Color(hex: 0xA9B2AD)
    static let stageLine = Color(hex: 0xECE7DE, alpha: 0.12)
    static let stageAccent = Color(hex: 0xC2673F)

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
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        let attrs: [UIFontDescriptor.AttributeName: Any] = [
            .name: "Fraunces",
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                wght: weight, opsz: min(144, max(9, size)), soft: 60,
            ],
        ]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attrs), size: scaled)
        if font.familyName.lowercased().contains("fraunces") {
            return Font(font as CTFont)
        }
        return .system(size: scaled, weight: .regular, design: .serif)
    }
}

extension Font {
    static let barrierDisplay = Typeface.display(36)
    static let barrierTitle = Typeface.display(30, weight: 440, relativeTo: .title)
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
