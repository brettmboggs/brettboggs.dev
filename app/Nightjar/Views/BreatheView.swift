import SwiftUI

/// Pick a pattern and a length. The session itself is full screen.
struct BreatheView: View {
    @Environment(PlayerController.self) private var player

    @State private var selectedID: String = "478"
    @State private var showCustom = false

    private let lengths = [2, 3, 5, 10, 15]

    var body: some View {
        @Bindable var settings = player.settings

        return VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle(title: "Breathe", subtitle: "The screen breathes with you.") {
                        EmptyView()
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: 200)

                    VStack(spacing: 0) {
                        ForEach(BreathPattern.library) { pattern in
                            patternRow(pattern)
                            Hairline()
                        }
                        patternRow(BreathPattern.custom(settings.customBreath), isCustom: true)
                    }

                    SectionLabel("For")
                        .padding(.top, 26)
                    ChoiceRow(
                        options: lengths.map { ($0, "\($0) min") },
                        selection: settings.breathMinutes
                    ) { choice in
                        settings.breathMinutes = choice
                        settings.save()
                    }
                    .padding(.top, 8)

                    HStack(spacing: 22) {
                        Toggle("", isOn: Binding(
                            get: { settings.breathGuideSound },
                            set: { player.setBreathGuide(enabled: $0) }
                        ))
                        .toggleStyle(WarmToggleStyle())
                        .labelsHidden()
                        Text("Breath sound")
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.inkSoft)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { settings.breathHaptics },
                            set: { settings.breathHaptics = $0; settings.save() }
                        ))
                        .toggleStyle(WarmToggleStyle())
                        .labelsHidden()
                        Text("Taps")
                            .font(Typeface.body(14))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.top, 20)

                    SoftButton(title: "Begin", systemImage: "wind", isProminent: true, isWide: true) {
                        begin()
                    }
                    .padding(.top, 26)

                // The notes are sleep hygiene, and the patterns are breathing
                // exercises. Neither is medical advice, and one of them has a
                // real contraindication, so say so where they are used rather
                // than only in the terms.
                Text("Breathing exercises are not medical advice. If you have a heart or breathing condition, talk to a doctor first.")
                    .font(Typeface.body(11))
                    .foregroundStyle(Palette.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)

                    Color.clear.frame(height: 96)
                }
                .pageGutter()
            }
        }
        .sheet(isPresented: $showCustom) { CustomBreathSheet() }
        .onAppear { selectedID = player.routinePattern.id }
    }

    private func patternRow(_ pattern: BreathPattern, isCustom: Bool = false) -> some View {
        let isSelected = selectedID == pattern.id
        let locked = !player.plan.allows(pattern)
        return Button {
            if locked {
                player.requestUpgrade(.breath)
                return
            }
            withAnimation(.settle) { selectedID = pattern.id }
            if isCustom { showCustom = true }
        } label: {
            IndexRow(title: pattern.name, detail: "\(pattern.signature)   \(pattern.blurb)", isActive: isSelected) {
                HStack(spacing: 10) {
                    if locked { PlusMark() }
                    if isSelected {
                        OrbMark(size: 18, isLit: true)
                    } else if isCustom {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func begin() {
        let pattern = BreathPattern.named(selectedID, custom: player.settings.customBreath)
        // Remember the choice, so the tab and the routine come back to it.
        if player.plan.allows(pattern) {
            player.settings.routineBreathPatternID = pattern.id
        }
        player.startBreath(pattern, minutes: player.settings.breathMinutes)
    }
}

// MARK: - Custom pattern

struct CustomBreathSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    private let labels = ["In", "Hold", "Out", "Rest"]

    var body: some View {
        @Bindable var settings = player.settings

        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Your own", subtitle: "Seconds for each part. Zero skips it.", onClose: { dismiss() })

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    let value = settings.customBreath.indices.contains(index) ? settings.customBreath[index] : 4
                    SettingRow(title: labels[index]) {
                        HStack(spacing: 14) {
                            IconButton(systemImage: "minus", size: 30) {
                                set(index, max(value - 1, index == 1 || index == 3 ? 0 : 1))
                            }
                            Text(Format.seconds(value))
                                .font(Typeface.meta(16, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 34)
                            IconButton(systemImage: "plus", size: 30) {
                                set(index, min(value + 1, 20))
                            }
                        }
                    }
                    Hairline()
                }
            }
            .padding(.top, 18)

            Text(BreathPattern.custom(settings.customBreath).signature + " · " + String(format: "%.1f breaths a minute", BreathPattern.custom(settings.customBreath).breathsPerMinute))
                .font(Typeface.meta(12))
                .foregroundStyle(Palette.inkFaint)
                .padding(.top, 16)

            Spacer(minLength: 16)
        }
        .pageGutter()
        .sheetDressing()
        .presentationDetents([.height(420)])
        .paywallHost()
    }

    private func set(_ index: Int, _ value: Double) {
        var values = player.settings.customBreath
        if values.count != 4 { values = [4, 4, 6, 2] }
        values[index] = value
        player.settings.customBreath = values
        player.settings.save()
    }
}

// MARK: - The session

/// Full screen. The orb is the instruction; the words are a courtesy.
struct BreathSessionView: View {
    @Environment(PlayerController.self) private var player
    let session: BreathSession

    @State private var now = Date()
    private let clock = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
            LivingCanvas(
                energy: 0,
                intensity: 1.1,
                rim: 0.7,
                centerY: 0.44,
                frameRate: 60,
                breath: { date in session.fullness(at: date) }
            )

            VStack(spacing: 0) {
                HStack {
                    Text(session.pattern.name)
                        .font(Typeface.display(20))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text(Format.clock(session.remaining))
                        .font(Typeface.meta(13))
                        .foregroundStyle(Palette.inkFaint)
                        .monospacedDigit()
                }
                .pageGutter()
                .padding(.top, 8)

                Spacer().frame(height: max(geo.size.height * 0.64 - 60, 40))

                VStack(spacing: 8) {
                    Text(phaseLabel)
                        .font(Typeface.display(34))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.opacity)
                        .animation(.settle, value: phaseLabel)
                    Text(String(Int(session.phaseRemaining(at: now).rounded(.up))))
                        .font(Typeface.meta(15))
                        .foregroundStyle(Palette.inkSoft)
                        .monospacedDigit()
                        .opacity(session.isPaused ? 0.3 : 1)
                }

                Spacer()

                HStack(spacing: 14) {
                    SoftButton(
                        title: session.isPaused ? "Resume" : "Pause",
                        systemImage: session.isPaused ? "play.fill" : "pause.fill"
                    ) {
                        if session.isPaused {
                            player.resumeBreath()
                        } else {
                            player.pauseBreath()
                        }
                    }
                    Spacer()
                    if player.routineStage == .breathing {
                        Text("Then \(player.routineMix.name)")
                            .font(Typeface.meta(11))
                            .foregroundStyle(Palette.inkFaint)
                        Spacer()
                    }
                    SoftButton(title: player.routineStage == .breathing ? "Skip to sound" : "End", systemImage: "checkmark") {
                        player.endBreath()
                    }
                }
                .pageGutter()
                .padding(.bottom, 26)
            }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onReceive(clock) { date in now = date }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var phaseLabel: String {
        if session.isPaused { return "Paused" }
        return session.currentPhase?.kind.label ?? "Breathe"
    }
}
