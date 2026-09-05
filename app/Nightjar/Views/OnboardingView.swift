import SwiftUI

/// Three screens, no account, no permission prompts. Ends on the Tonight
/// screen with a mix already loaded.
struct OnboardingView: View {
    @Environment(PlayerController.self) private var player

    @State private var step = 0
    @State private var goal: SleepGoal = .fallAsleep
    @State private var bedtime = Date()

    var body: some View {
        ZStack {
            LivingCanvas(
                energy: 0,
                intensity: step == 0 ? 1.1 : 0.7,
                rim: step == 0 ? 0.3 : 0.12,
                centerY: step == 0 ? 0.42 : 0.16,
                frameRate: 30
            )
            .animation(.settleSlow, value: step)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                switch step {
                case 0: welcome
                case 1: goals
                default: bedtimeStep
                }
            }
            .pageGutter()
        }
        .onAppear {
            bedtime = date(minuteOfDay: player.settings.bedtimeMinuteOfDay)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Slumbio")
                .font(Typeface.display(46))
                .foregroundStyle(Palette.ink)
            Text("Sound that never loops. Breathing you can see. Nothing to sign up for.")
                .font(Typeface.body(16))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            SoftButton(title: "Begin", isProminent: true, isWide: true) {
                withAnimation(.settleSlow) { step = 1 }
            }
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What brings you here?")
                .font(Typeface.display(32))
                .foregroundStyle(Palette.ink)
            Text("It only picks where you start.")
                .font(Typeface.body(14))
                .foregroundStyle(Palette.inkSoft)
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(SleepGoal.allCases) { option in
                    Button {
                        withAnimation(.settle) { goal = option }
                        Haptics.tap(enabled: true)
                    } label: {
                        IndexRow(title: option.title, isActive: goal == option) {
                            if goal == option { OrbMark(size: 18, isLit: true) }
                        }
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
            .padding(.top, 22)

            SoftButton(title: "Next", isProminent: true, isWide: true) {
                withAnimation(.settleSlow) { step = 2 }
            }
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
    }

    private var bedtimeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("When do you turn in?")
                .font(Typeface.display(32))
                .foregroundStyle(Palette.ink)
            Text("Roughly. You can change it later, and nothing will buzz you unless you ask.")
                .font(Typeface.body(14))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            SoftButton(title: "Done", isProminent: true, isWide: true) {
                finish()
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func finish() {
        let settings = player.settings
        settings.goal = goal
        settings.routineBreathPatternID = goal.breathPatternID
        let components = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        settings.bedtimeMinuteOfDay = (components.hour ?? 22) * 60 + (components.minute ?? 30)
        settings.hasOnboarded = true
        settings.save()
        player.load(Mix.recommended(for: goal))
        Haptics.success(enabled: true)
    }

    private func date(minuteOfDay: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        return Calendar.current.date(from: components) ?? Date()
    }
}
