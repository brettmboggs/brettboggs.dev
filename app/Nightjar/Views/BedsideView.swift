import SwiftUI
import UIKit

/// A clock and almost nothing else. Drops the screen brightness, keeps it
/// awake, and hides every control until you touch it.
struct BedsideView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var showControls = true
    @State private var lastTouch = Date()
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LivingCanvas(
                energy: player.isPlaying ? player.meterLevel * 0.5 : 0,
                intensity: 0.28,
                rim: 0.03,
                centerY: 0.5,
                frameRate: 8
            )

            VStack(spacing: 10) {
                Spacer()
                Text(Format.timeOfDay(now))
                    .font(Typeface.display(72))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                    .monospacedDigit()
                Text(statusLine)
                    .font(Typeface.body(14))
                    .foregroundStyle(Palette.inkFaint)
                Spacer()
                if showControls {
                    HStack(spacing: 14) {
                        SoftButton(title: "Leave", systemImage: "arrow.down.right.and.arrow.up.left") {
                            dismiss()
                        }
                        Spacer()
                        SoftButton(
                            title: player.isPlaying ? "Pause" : "Play",
                            systemImage: player.isPlaying ? "pause.fill" : "play.fill"
                        ) {
                            player.toggle()
                        }
                        if player.timerEnd != nil {
                            SoftButton(title: "+15", systemImage: "plus") {
                                player.extendTimer(byMinutes: 15)
                            }
                        }
                    }
                    .pageGutter()
                    .padding(.bottom, 30)
                    .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .paywallHost()
        .contentShape(Rectangle())
        .onTapGesture { touched() }
        .onReceive(clock) { date in
            now = date
            if showControls, date.timeIntervalSince(lastTouch) > 6 {
                withAnimation(.settleSlow) { showControls = false }
            }
        }
        .onAppear {
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 0.02
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = savedBrightness
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding does not fire onDisappear. Hand the brightness back.
            UIScreen.main.brightness = phase == .active ? 0.02 : savedBrightness
        }
    }

    private var statusLine: String {
        if player.isPlaying {
            if let remaining = player.timerRemaining {
                return "\(player.currentMix.name) · \(Format.clock(remaining))"
            }
            return player.currentMix.name
        }
        if let alarm = player.nextAlarm, player.settings.alarmEnabled {
            return "Alarm \(Format.timeOfDay(alarm))"
        }
        return "Quiet"
    }

    private func touched() {
        lastTouch = Date()
        withAnimation(.settle) { showControls = true }
    }
}
