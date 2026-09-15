import SwiftUI
import UIKit

/// Black on white by day, white on black by night, greys in between.
///
/// Everything routes through the system semantic colours, which is what
/// makes the palette exactly two colours: `systemBackground` is pure white
/// in light mode and pure black in dark mode on an iPhone, and `primary`
/// is the opposite. There is no accent colour. Emphasis is done with weight,
/// size and space, the way a printed cookbook does it.
enum Ink {
    static let paper = Color(uiColor: .systemBackground)
    static let paperRaised = Color(uiColor: .secondarySystemBackground)
    static let paperSunken = Color(uiColor: .tertiarySystemFill)
    static let ink = Color.primary
    static let inkSoft = Color.secondary
    static let inkFaint = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: .separator)
}

enum Typeface {
    /// Designed sizes, scaled by whatever text size the reader has set, and
    /// capped so the layouts keep their shape. Cook mode has its own, bigger
    /// scale on top of this.
    private static func scaled(_ size: CGFloat, relativeTo style: UIFont.TextStyle) -> CGFloat {
        min(UIFontMetrics(forTextStyle: style).scaledValue(for: size), size * 1.4)
    }

    /// The system serif, for recipe titles and nothing else. It is what makes
    /// a screen of recipes read like a book rather than a settings pane.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, relativeTo: .title2), weight: weight, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size, relativeTo: .body), weight: weight, design: .default)
    }

    /// Metadata: times, counts, step numbers, section labels.
    static func meta(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: scaled(size, relativeTo: .caption1), weight: weight, design: .monospaced)
    }
}

/// Long, quiet ease-out.
extension Animation {
    static var settle: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.45) }
}
