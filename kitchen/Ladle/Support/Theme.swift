import SwiftUI
import UIKit

/// Clean system surfaces with one warm color.
///
/// Paper and ink route through the system semantic colors, so light and
/// dark mode come for free. The accent is a tomato red, used for things that
/// are on: check marks, what the kitchen has, the one main button on a screen.
/// Everything else is black, white and grays.
enum Ink {
    static let paper = Color(uiColor: .systemBackground)
    static let paperRaised = Color(uiColor: .secondarySystemBackground)
    static let paperSunken = Color(uiColor: .tertiarySystemFill)
    static let ink = Color.primary
    static let inkSoft = Color.secondary
    static let inkFaint = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: .separator)

    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.42, blue: 0.30, alpha: 1)
            : UIColor(red: 0.82, green: 0.26, blue: 0.16, alpha: 1)
    })
    /// Text and icons that sit on the accent.
    static let onAccent = Color.white
}

enum Typeface {
    /// Designed sizes, scaled by whatever text size the reader has set, and
    /// capped so the layouts keep their shape. Cook mode has its own, bigger
    /// scale on top of this.
    private static func scaled(_ size: CGFloat, relativeTo style: UIFont.TextStyle) -> CGFloat {
        min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * 1.4)
    }

    /// Instrument Serif, bundled in Fonts/, for screen and recipe titles only.
    /// It is a tall, narrow face, so it is set a size up from the designed
    /// number to sit level with the system text around it. It has one weight;
    /// `weight` is accepted so call sites read the same as `body`.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", fixedSize: scaled(size * 1.18, relativeTo: .title2))
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, relativeTo: .body), weight: weight, design: .default)
    }

    /// Metadata: times, counts, step numbers. Plain system text with even
    /// digits, so numbers line up without looking like a terminal.
    static func meta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size + 1, relativeTo: .caption1), weight: weight, design: .default).monospacedDigit()
    }
}

/// Long, quiet ease-out.
extension Animation {
    static var settle: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.45) }
}
