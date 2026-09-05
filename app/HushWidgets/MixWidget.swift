import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: PlaybackSnapshot
}

struct MixProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? PlaybackSnapshot.placeholder : SharedStore.readSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let entry = SnapshotEntry(date: Date(), snapshot: snapshot)
        // The app reloads the timeline whenever state changes, so this is only
        // a backstop for a widget that has been sitting untouched.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MixWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: MixProvider()) { entry in
            MixWidgetView(entry: entry)
                .containerBackground(Palette.ground, for: .widget)
        }
        .configurationDisplayName("Hush")
        .description("Start or stop your sound without opening the app.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct MixWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(entry.snapshot.isPlaying ? entry.snapshot.mixName : "Hush")
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HUSH")
                    .font(Typeface.meta(9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                if entry.snapshot.isPlaying {
                    Circle()
                        .fill(Palette.ember)
                        .frame(width: 6, height: 6)
                }
            }

            Spacer(minLength: 6)

            Text(entry.snapshot.mixName)
                .font(Typeface.display(19))
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let end = entry.snapshot.timerEnd, end > Date() {
                Text(end, style: .timer)
                    .font(Typeface.meta(10))
                    .foregroundStyle(Palette.ember.opacity(0.9))
                    .monospacedDigit()
            }

            Spacer(minLength: 6)

            toggleButton
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HUSH")
                    .font(Typeface.meta(9, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(Palette.inkFaint)

                Text(entry.snapshot.mixName)
                    .font(Typeface.display(24))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(entry.snapshot.mixSummary)
                    .font(Typeface.meta(9))
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let end = entry.snapshot.timerEnd, end > Date() {
                    HStack(spacing: 5) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9))
                        Text(end, style: .timer)
                            .monospacedDigit()
                    }
                    .font(Typeface.meta(10))
                    .foregroundStyle(Palette.ember.opacity(0.9))
                } else if let wake = entry.snapshot.wakeAt {
                    HStack(spacing: 5) {
                        Image(systemName: "sunrise")
                            .font(.system(size: 9))
                        Text(Format.timeOfDay(wake))
                    }
                    .font(Typeface.meta(10))
                    .foregroundStyle(Palette.inkFaint)
                }
            }

            Spacer(minLength: 0)
            toggleButton
        }
    }

    private var toggleButton: some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entry.snapshot.isPlaying ? Palette.ground : Palette.ink)
                .frame(width: 42, height: 42)
                .background(
                    Circle().fill(
                        entry.snapshot.isPlaying ? Palette.ember : Palette.raisedHigh
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.snapshot.isPlaying ? "waveform" : "moon.zzz")
                .font(.system(size: 18, weight: .medium))
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.snapshot.isPlaying ? "Playing" : "Paused")
                .font(.system(size: 11, weight: .semibold))
            Text(entry.snapshot.mixName)
                .font(.system(size: 14))
                .lineLimit(1)
            if let end = entry.snapshot.timerEnd, end > Date() {
                Text(end, style: .timer)
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
