import AppIntents
import SwiftUI
import WidgetKit

/// The colours are repeated here rather than shared with the app.
///
/// A widget extension is its own module. Handing it `Palette` would mean
/// handing it the sound catalogue that `Palette.tint(for:)` depends on, and
/// then the model behind that. Five hex values is the cheaper duplication.
enum WidgetPalette {
    static let ground = Color(red: 0.051, green: 0.043, blue: 0.035)
    static let raised = Color(red: 0.102, green: 0.082, blue: 0.063)
    static let ink = Color(red: 0.945, green: 0.906, blue: 0.851)
    static let inkSoft = Color(red: 0.671, green: 0.620, blue: 0.553)
    static let ember = Color(red: 0.910, green: 0.627, blue: 0.306)
}

/// The icon, in miniature: a sun going down behind a ridge.
struct SunMark: View {
    var size: CGFloat = 38

    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [WidgetPalette.ember.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
                .frame(width: size * 1.7, height: size * 1.7)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.99, green: 0.94, blue: 0.85), WidgetPalette.ember],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.86, height: size * 0.86)
                .offset(y: size * 0.16)
                .mask(alignment: .top) {
                    Rectangle().frame(height: size * 0.72)
                }
            Rectangle()
                .fill(WidgetPalette.ember.opacity(0.85))
                .frame(height: 1.5)
                .frame(maxWidth: size * 1.5)
        }
        .frame(width: size * 1.7, height: size)
    }
}

// MARK: - Home screen

struct WindDownEntry: TimelineEntry {
    let date: Date
}

/// Nothing to refresh. The widget is a set of doors, not a readout: without an
/// App Group there is nothing of the app's state to read, and a widget that
/// lies about how long you slept would be worse than one that does not say.
struct WindDownProvider: TimelineProvider {
    func placeholder(in context: Context) -> WindDownEntry { WindDownEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (WindDownEntry) -> Void) {
        completion(WindDownEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WindDownEntry>) -> Void) {
        completion(Timeline(entries: [WindDownEntry(date: .now)], policy: .never))
    }
}

struct SlumbioWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            SunMark(size: 34)
            Spacer(minLength: 8)
            Text("Wind down")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .foregroundStyle(WidgetPalette.ink)
            Text("A breath, then sound, then the timer.")
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.inkSoft)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "slumbio://winddown"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SunMark(size: 30)
                Spacer(minLength: 0)
                Text("Slumbio")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(WidgetPalette.ink)
            }
            VStack(spacing: 7) {
                door("Wind down", "moon.zzz", "slumbio://winddown", prominent: true)
                door("Play", "waveform", "slumbio://play")
                door("Breathe", "wind", "slumbio://breathe")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func door(_ title: String, _ symbol: String, _ url: String, prominent: Bool = false) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominent ? WidgetPalette.ground : WidgetPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? WidgetPalette.ember : WidgetPalette.raised)
            )
        }
    }
}

struct SlumbioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "dev.brettboggs.nightjar.widget", provider: WindDownProvider()) { _ in
            SlumbioWidgetView()
                .containerBackground(for: .widget) {
                    WidgetPalette.ground
                }
        }
        .configurationDisplayName("Wind down")
        .description("One tap into the routine, the sound or a breath.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Control Centre

/// The point of this one: it is reachable with the phone face down on the
/// nightstand and the screen almost off, which is exactly when someone wants
/// to start winding down and exactly when they should not be handed a lit
/// home screen to hunt through.
struct WindDownControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.brettboggs.nightjar.control.winddown") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "slumbio://winddown")!)) {
                Label("Wind Down", systemImage: "moon.zzz")
            }
        }
        .displayName("Wind Down")
        .description("A breath, then the sound, then the sleep timer.")
    }
}

struct PlayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.brettboggs.nightjar.control.play") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "slumbio://play")!)) {
                Label("Play Slumbio", systemImage: "waveform")
            }
        }
        .displayName("Play Slumbio")
        .description("Starts the mix on the Tonight screen.")
    }
}

// MARK: - Bundle

@main
struct SlumbioWidgetBundle: WidgetBundle {
    var body: some Widget {
        SlumbioWidget()
        WindDownControl()
        PlayControl()
    }
}
