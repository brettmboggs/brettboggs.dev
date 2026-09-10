import SwiftUI

/// Pick a pattern and a length, then begin.
///
/// One screen, one decision, and the decision is visible before it is made.
/// The ring is the selected pattern actually running, so swiping from
/// 4 · 7 · 8 to Box re-proportions it in front of you: the shape of a pattern
/// is felt before any of its numbers are read. That is the whole argument of
/// this tab, and it used to be buried under six list rows.
///
/// Everything that is not that decision has left. The breath sound and the
/// taps are preferences, set once and forgotten, so they live in Settings.
struct BreatheView: View {
    @Environment(PlayerController.self) private var player

    @State private var selectedID: String = BreathPattern.fourSevenEight.id
    @State private var showCustom = false

    private let lengthOptions = [2, 3, 5, 10, 15]

    private var patterns: [BreathPattern] {
        BreathPattern.library + [BreathPattern.custom(player.settings.customBreath)]
    }

    private var selectedPattern: BreathPattern {
        BreathPattern.named(selectedID, custom: player.settings.customBreath)
    }

    var body: some View {
        @Bindable var settings = player.settings

        return GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ScreenTitle(title: "Breathe", subtitle: "Swipe to change the shape.") {
                        EmptyView()
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 20)

                    BreathPreview(pattern: selectedPattern)
                        .animation(.settleSlow, value: selectedID)

                    pager
                        .padding(.top, 6)

                    Spacer(minLength: 24)

                    length(settings)

                    beginButton
                        .padding(.top, 20)

                    disclaimer
                        .padding(.top, 18)
                        .padding(.bottom, 96)
                }
                .pageGutter()
                // Fills the screen so the spacers have slack to share out. The
                // scroll view only actually scrolls when the content outgrows
                // this, which is a small phone or a large text size.
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .sheet(isPresented: $showCustom) { CustomBreathSheet() }
            .onAppear {
                selectedID = player.routinePattern.id
                snapLengthToAnOption()
            }
            .onChange(of: selectedID) { _, _ in
                Haptics.tap(enabled: player.settings.hapticsEnabled)
            }
        }
    }

    /// The stored default was four minutes, which is not one of the five
    /// choices, so the row came up with nothing selected and the screen looked
    /// broken before it was touched. Anything off the list moves to the
    /// nearest thing on it, once, quietly.
    private func snapLengthToAnOption() {
        let current = player.settings.breathMinutes
        guard !lengthOptions.contains(current) else { return }
        let nearest = lengthOptions.min { abs($0 - current) < abs($1 - current) } ?? 5
        player.settings.breathMinutes = nearest
        player.settings.save()
    }

    // MARK: - Choosing

    /// The system pager rather than a hand-rolled drag, so it carries the
    /// rubber-banding and the momentum people already expect from one. Its own
    /// dots are hidden and redrawn below in the app's colours; the built-in
    /// ones can only be tinted through a global UIKit appearance proxy, which
    /// is a large hammer for six small circles.
    private var pager: some View {
        VStack(spacing: 16) {
            TabView(selection: $selectedID) {
                ForEach(patterns) { pattern in
                    card(for: pattern).tag(pattern.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 116)

            HStack(spacing: 7) {
                ForEach(patterns) { pattern in
                    Circle()
                        .fill(pattern.id == selectedID ? Palette.ember : Palette.hairline)
                        .frame(width: 5, height: 5)
                }
            }
            .animation(.settle, value: selectedID)
            .accessibilityHidden(true)
        }
    }

    private func card(for pattern: BreathPattern) -> some View {
        let locked = !player.plan.allows(pattern)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(pattern.name)
                    .font(Typeface.display(27))
                    .foregroundStyle(locked ? Palette.inkSoft : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if locked { PlusMark() }
                if pattern.id == "custom", !locked {
                    Button { showCustom = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit your pattern")
                }
            }
            // 4 · 7 · 8 is its own signature, so printing both is stutter.
            if pattern.name != pattern.signature {
                Text(pattern.signature)
                    .font(Typeface.meta(13))
                    .foregroundStyle(Palette.ember.opacity(0.9))
                    .monospacedDigit()
            }
            Text(pattern.blurb)
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pattern.name), \(pattern.signature)")
        .accessibilityHint(pattern.blurb)
    }

    // MARK: - Length and start

    private func length(_ settings: Settings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("For")
            ChoiceRow(
                options: lengthOptions.map { ($0, "\($0) min") },
                selection: settings.breathMinutes
            ) { choice in
                settings.breathMinutes = choice
                settings.save()
                Haptics.tap(enabled: settings.hapticsEnabled)
            }
        }
    }

    /// Says what it will do. A locked pattern used to make this button do
    /// nothing at all, which reads as a bug rather than as a price.
    private var beginButton: some View {
        let locked = !player.plan.allows(selectedPattern)
        return SoftButton(
            title: locked ? "Unlock with Plus" : "Begin",
            systemImage: locked ? "lock" : "wind",
            isProminent: true,
            isWide: true
        ) {
            if locked {
                player.requestUpgrade(.breath)
            } else {
                begin()
            }
        }
    }

    // The notes are sleep hygiene, and the patterns are breathing exercises.
    // Neither is medical advice, and one of them has a real contraindication,
    // so say so where they are used rather than only in the terms.
    private var disclaimer: some View {
        Text("Breathing exercises are not medical advice. If you have a heart or breathing condition, talk to a doctor first.")
            .font(Typeface.body(11))
            .foregroundStyle(Palette.inkFaint)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func begin() {
        let pattern = selectedPattern
        // Remember the choice, so the tab and the routine come back to it.
        player.settings.routineBreathPatternID = pattern.id
        player.settings.save()
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


// MARK: - The preview

/// The selected pattern, breathing, before you commit to it.
///
/// The ring is the pattern's own shape: one arc per phase, each as long as
/// that phase is, so 4 · 7 · 8 looks lopsided and Box looks square before you
/// have read a single number. The arc you are in fills as it runs, and the
/// disc in the middle is the lungs.
struct BreathPreview: View {
    let pattern: BreathPattern
    var size: CGFloat = 178

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A hair of space between arcs, as a fraction of the circle.
    private let gap = 0.006

    /// Held at the top of the first inhale when motion is reduced: the arcs
    /// still show the pattern's proportions and the disc is still full, so the
    /// shape reads without anything moving. The timeline is slowed to match,
    /// rather than redrawing thirty times a second to show the same frame.
    private var frozenElapsed: Double {
        (pattern.phases.first?.seconds ?? 1) * 0.999
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 10 : 1 / 30)) { timeline in
            let elapsed = reduceMotion
                ? frozenElapsed
                : timeline.date.timeIntervalSinceReferenceDate
            let fullness = pattern.fullness(at: elapsed)
            let active = pattern.phase(at: elapsed)
            let phase = pattern.phases[min(active.index, pattern.phases.count - 1)]

            ZStack {
                // A soft well under the ring. The orb is still behind all of
                // this, and without somewhere dark to sit the numbers wash
                // straight out into it.
                Circle()
                    .fill(Palette.ground.opacity(0.62))
                    .frame(width: size * 0.98, height: size * 0.98)
                    .blur(radius: 20)

                ForEach(Array(spans.enumerated()), id: \.offset) { index, span in
                    let isActive = index == active.index
                    arc(from: span.start + gap, to: span.end - gap)
                        .stroke(
                            isActive ? Palette.ember.opacity(0.28) : Palette.hairline,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                    if isActive {
                        let head = span.start + (span.end - span.start) * active.progress
                        arc(from: span.start + gap, to: max(head - gap, span.start + gap))
                            .stroke(
                                Palette.ember,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                    }
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Palette.ember.opacity(0.34),
                                Palette.emberDeep.opacity(0.16),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.42
                        )
                    )
                    .frame(width: size * 0.82, height: size * 0.82)
                    .scaleEffect(0.42 + fullness * 0.58)

                VStack(spacing: 6) {
                    Text(phase.kind.label)
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkSoft)
                        .contentTransition(.opacity)
                        .animation(.settle, value: phase.kind)
                    Text(String(Int((phase.seconds * (1 - active.progress)).rounded(.up))))
                        .font(Typeface.display(30))
                        .foregroundStyle(Palette.ink)
                        .monospacedDigit()
                }
            }
            .frame(width: size, height: size)
        }
        .frame(height: size)
        .accessibilityHidden(true)
    }

    /// Where each phase starts and ends around the circle, 0...1.
    private var spans: [(start: Double, end: Double)] {
        let total = max(pattern.cycleSeconds, 0.001)
        var running = 0.0
        return pattern.phases.map { phase in
            let start = running / total
            running += phase.seconds
            return (start, running / total)
        }
    }

    /// Trimmed circle, rotated so zero is at the top.
    private func arc(from start: Double, to end: Double) -> some Shape {
        Circle()
            .trim(from: start, to: max(end, start))
            .rotation(.degrees(-90))
    }
}
