import Combine
import SwiftUI
import UIKit

/// A clock you can leave face-up on the nightstand.
///
/// Drops the screen brightness to near nothing, keeps the display awake, and
/// hides every control until you touch it.
struct BedsideView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var lastTouch = Date()
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BreathingBackdrop(
                level: player.meterLevel,
                isPlaying: player.isPlaying,
                intensity: 0.30
            )
            .opacity(0.55)

            VStack(spacing: 14) {
                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Format.timeOfDay(context.date))
                        .font(Typeface.display(76, weight: .light))
                        .foregroundStyle(Palette.ink.opacity(showControls ? 0.92 : 0.55))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }

                VStack(spacing: 6) {
                    Text(player.currentMix.name.uppercased())
                        .font(Typeface.meta(11))
                        .tracking(2.4)
                        .foregroundStyle(Palette.inkFaint)

                    if let remaining = player.timerRemaining {
                        Text(Format.clock(remaining))
                            .font(Typeface.meta(12))
                            .foregroundStyle(Palette.ember.opacity(0.7))
                            .monospacedDigit()
                    }

                    if let alarm = player.nextAlarm, player.settings.alarmEnabled {
                        Text("Alarm \(Format.timeOfDay(alarm))")
                            .font(Typeface.meta(10))
                            .tracking(1.2)
                            .foregroundStyle(Palette.inkFaint.opacity(0.8))
                    }
                }

                Spacer()

                controls
                    .opacity(showControls ? 1 : 0)
                    .animation(.settleSlow, value: showControls)
            }
            .padding(.bottom, 40)
            .pageGutter()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            lastTouch = Date()
            withAnimation(.settle) { showControls = true }
        }
        .onReceive(tick) { _ in
            if showControls, Date().timeIntervalSince(lastTouch) > 6 {
                withAnimation(.settleSlow) { showControls = false }
            }
        }
        .statusBarHidden()
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIApplication.shared.isIdleTimerDisabled = true
            withAnimation(.easeInOut(duration: 1.6)) {
                UIScreen.main.brightness = 0.02
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            UIScreen.main.brightness = previousBrightness
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 46, height: 46)
                    .background(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 60, height: 60)
                    .background(Circle().strokeBorder(Palette.ink.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                player.extendTimer(byMinutes: 15)
            } label: {
                Text("+15")
                    .font(Typeface.meta(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 46, height: 46)
                    .background(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}
