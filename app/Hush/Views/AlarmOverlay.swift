import SwiftUI

/// Shown over everything when the alarm lands.
struct AlarmOverlay: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            BreathingBackdrop(level: player.meterLevel, isPlaying: true, intensity: 1)

            VStack(spacing: 18) {
                Spacer()

                Text("Good morning")
                    .font(Typeface.display(38))
                    .foregroundStyle(Palette.ink)

                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Format.timeOfDay(context.date))
                        .font(Typeface.meta(15))
                        .tracking(1.6)
                        .foregroundStyle(Palette.ember)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        player.dismissAlarm()
                    } label: {
                        Text("Stop")
                            .font(Typeface.body(16, weight: .semibold))
                            .foregroundStyle(Palette.ground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                Capsule().fill(Palette.ember)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.snoozeAlarm()
                    } label: {
                        Text("Snooze 9 minutes")
                            .font(Typeface.body(15))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                Capsule().strokeBorder(Palette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 46)
            }
            .pageGutter()
        }
        .transition(.opacity)
    }
}
