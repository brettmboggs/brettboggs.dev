import SwiftUI

/// The app is dark-only on purpose: it is looked at in a dark room by someone
/// trying to fall asleep. Every accent is warm and low-blue for the same reason.
public enum Palette {
    public static let ground = Color(hex: 0x0C0A09)
    public static let raised = Color(hex: 0x16120E)
    public static let raisedHigh = Color(hex: 0x1F1913)
    public static let hairline = Color(hex: 0x2E2620)

    public static let ink = Color(hex: 0xF0E6D8)
    public static let inkSoft = Color(hex: 0xA99C8B)
    public static let inkFaint = Color(hex: 0x6B6055)

    public static let ember = Color(hex: 0xE39A4A)
    public static let emberDeep = Color(hex: 0xC2703A)
    public static let clay = Color(hex: 0x8C5A3C)
    public static let moss = Color(hex: 0x6E7A52)
    public static let dusk = Color(hex: 0x5A6076)

    /// Accent for a sound family, used by the level meters and library rows.
    public static func tint(for family: SoundFamily) -> Color {
        switch family {
        case .recorded: return Color(hex: 0xD9A05B)
        case .rain: return Color(hex: 0x7E93A6)
        case .water: return Color(hex: 0x6E8C86)
        case .wind: return Color(hex: 0x8D9478)
        case .fire: return Color(hex: 0xD4783C)
        case .living: return Color(hex: 0x7F9464)
        case .machines: return Color(hex: 0x9A8B76)
        case .places: return Color(hex: 0x7C7392)
        case .tones: return Color(hex: 0xB08AA6)
        case .noise: return Color(hex: 0xC9A06A)
        }
    }
}

public enum Typeface {
    /// Serif display. Uses the system serif so there are no font files to ship
    /// and nothing to license.
    public static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    public static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Metadata, counters, timers.
    public static func meta(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Long, warm ease-out. Nothing in this app should arrive quickly.
public extension Animation {
    static var settle: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.55) }
    static var settleSlow: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.9) }
}
