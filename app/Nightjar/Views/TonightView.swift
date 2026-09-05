import SwiftUI

/// The front door. One mix, one button, one breath.
struct TonightView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.openSettings) private var openSettings

    @State private var showTimer = false
    @State private var showRoutine = false
    @State private var showBedside = false
    @State private var showSave = false
    @State private var saveName = ""

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                    .pageGutter()
                // The orb is centred at 36% of the height. The name sits just
                // under its lower edge.
                Spacer().frame(height: max(geo.size.height * 0.50 - 120, 40))
                hero
                Spacer(minLength: 12)
                transport
                    .pageGutter()
                routineRow
                    .pageGutter()
                    .padding(.top, 18)
                note
                    .pageGutter()
                    .padding(.top, 22)
                    .padding(.bottom, 92)
            }
        }
        .onReceive(clock) { date in now = date }
        .onAppear { offerIfDue() }
        .onChange(of: player.pendingFirstNightOffer) { _, _ in offerIfDue() }
        .sheet(isPresented: $showTimer) { TimerSheet() }
        .sheet(isPresented: $showRoutine) { RoutineSheet() }
        .fullScreenCover(isPresented: $showBedside) { BedsideView() }
        .alert("Name this mix", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") {
                player.saveCurrentMix(named: saveName)
                saveName = ""
            }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("It will be under Sounds, with the others.")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center) {
            Text("Slumbio")
                .font(Typeface.display(20))
                .foregroundStyle(Palette.inkSoft)
            Spacer()
            if let streak = streakLine {
                Text(streak)
                    .font(Typeface.meta(11))
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.trailing, 10)
            }
            IconButton(systemImage: "moon.zzz") { showBedside = true }
            IconButton(systemImage: "slider.horizontal.3") { openSettings() }
        }
        .padding(.top, 8)
    }

    private var streakLine: String? {
        let streak = player.journal.streak
        guard streak >= 2 else { return nil }
        return "\(streak) nights running"
    }

    /// The orb lives behind this. The text sits just under it.
    private var hero: some View {
        VStack(spacing: 10) {
            Text(player.currentMix.isEmpty ? "Nothing playing" : player.currentMix.name)
                .font(Typeface.display(30))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
            Text(subtitle)
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
            if let remaining = player.previewRemaining {
                Chip(text: "Preview · \(Format.clock(remaining))", systemImage: "sparkles")
                    .padding(.top, 4)
            }
        }
        .pageGutter()
        .animation(.settle, value: player.currentMix.name)
    }

    private var subtitle: String {
        if player.currentMix.isEmpty { return "Pick a sound to begin" }
        if player.isWaking { return "Sunrise" }
        if let remaining = player.timerRemaining, player.isPlaying {
            return "\(player.currentMix.summary) · \(Format.clock(remaining))"
        }
        return player.currentMix.summary
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Button {
                showTimer = true
            } label: {
                Chip(
                    text: timerLabel,
                    systemImage: "timer",
                    isLit: player.timerEnd != nil && player.isPlaying
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                player.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(Palette.ember)
                        .frame(width: 72, height: 72)
                        .shadow(color: Palette.ember.opacity(player.isPlaying ? 0.45 : 0.2), radius: 22)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Palette.ground)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .disabled(player.currentMix.isEmpty)
            .opacity(player.currentMix.isEmpty ? 0.5 : 1)
            .animation(.settle, value: player.isPlaying)

            Spacer()

            Button {
                if player.currentMixIsUnsaved {
                    if player.canSaveAnotherMix {
                        saveName = player.currentMix.name
                        showSave = true
                    } else {
                        player.requestUpgrade(.mixes)
                    }
                } else {
                    player.surpriseMe()
                }
            } label: {
                Chip(
                    text: player.currentMixIsUnsaved ? "Save" : "Shuffle",
                    systemImage: player.currentMixIsUnsaved ? "bookmark" : "shuffle"
                )
            }
            .buttonStyle(.plain)
        }
        .animation(.settle, value: player.currentMixIsUnsaved)
    }

    private var timerLabel: String {
        if let remaining = player.timerRemaining, player.isPlaying {
            return Format.clock(remaining)
        }
        if player.settings.timerMinutes > 0 {
            return Format.minutes(player.settings.timerMinutes)
        }
        return "No timer"
    }

    /// One tap to bed. The routine is the app's whole argument in a line.
    private var routineRow: some View {
        HStack(spacing: 0) {
            Button {
                if player.isBreathing { return }
                player.startRoutine()
            } label: {
                HStack(spacing: 14) {
                    OrbMark(size: 26, isLit: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wind down")
                            .font(Typeface.body(16, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(routineLine)
                            .font(Typeface.body(12))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showRoutine = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.raised.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private var routineLine: String {
        let pattern = player.routinePattern.name
        let minutes = Format.minutes(player.settings.routineBreathMinutes)
        let mix = player.routineMix.name
        let timer = player.settings.routineTimerMinutes > 0
            ? Format.minutes(player.settings.routineTimerMinutes)
            : "no timer"
        return "\(pattern), \(minutes) · \(mix) · \(timer)"
    }

    private var note: some View {
        let tip = Tips.tonight(now)
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Tonight")
            Text(tip.title)
                .font(Typeface.body(15, weight: .medium))
                .foregroundStyle(Palette.ink)
            Text(tip.body)
                .font(Typeface.body(13))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The one soft offer

    private func offerIfDue() {
        guard player.pendingFirstNightOffer, !player.plan.isPlus, player.paywall == nil else { return }
        player.consumeFirstNightOffer()
        player.requestUpgrade(.firstNight)
    }
}

// MARK: - Sleep timer

struct TimerSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    private let choices = [0, 15, 30, 45, 60, 90, 120, 240, 480]

    var body: some View {
        @Bindable var settings = player.settings

        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Sleep timer",
                subtitle: "The sound fades out before it ends.",
                onClose: { dismiss() }
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(choices, id: \.self) { minutes in
                    let isSelected = settings.timerMinutes == minutes
                    Button {
                        player.setTimer(minutes: minutes)
                    } label: {
                        Text(minutes == 0 ? "Off" : Format.minutes(minutes))
                            .font(Typeface.meta(13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Palette.ground : Palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? Palette.ember : Palette.raised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 22)

            if player.timerEnd != nil, player.isPlaying {
                HStack {
                    Text("Ends at \(Format.timeOfDay(player.timerEnd ?? Date()))")
                        .font(Typeface.body(13))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    SoftButton(title: "+15 min", systemImage: "plus") {
                        player.extendTimer(byMinutes: 15)
                    }
                }
                .padding(.top, 18)
            }

            VStack(spacing: 0) {
                SettingRow(title: "When it ends", detail: "Fade to quiet keeps a near-silent bed running, which the sunrise alarm needs.") {
                    ChoiceRow(
                        options: TimerEndAction.allCases.map { ($0, $0.title) },
                        selection: settings.timerEndAction
                    ) { choice in
                        settings.timerEndAction = choice
                        settings.save()
                    }
                    .frame(width: 170)
                }
                Hairline()
                SettingRow(title: "Fade out", detail: "Minutes before the end that the fade begins.") {
                    ChoiceRow(
                        options: [(1.0, "1"), (5.0, "5"), (10.0, "10"), (20.0, "20")],
                        selection: settings.fadeOutMinutes
                    ) { choice in
                        settings.fadeOutMinutes = choice
                        settings.save()
                    }
                    .frame(width: 170)
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 20)
        }
        .pageGutter()
        .sheetDressing()
        .presentationDetents([.large])
        .paywallHost()
    }
}

// MARK: - Routine

struct RoutineSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = player.settings
        let editable = player.plan.isPlus

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader(
                    title: "Wind down",
                    subtitle: "A breath, then the sound, then the timer.",
                    onClose: { dismiss() }
                )

                if !editable {
                    HStack(spacing: 10) {
                        PlusMark()
                        Text("The routine runs free as it is. Changing it is part of Plus.")
                            .font(Typeface.body(13))
                            .foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.top, 18)
                    .onTapGesture { player.requestUpgrade(.routine) }
                }

                SectionLabel("Breath")
                    .padding(.top, 26)
                VStack(spacing: 0) {
                    ForEach(BreathPattern.library) { pattern in
                        let isSelected = settings.routineBreathPatternID == pattern.id
                        Button {
                            guard editable else { player.requestUpgrade(.routine); return }
                            guard player.plan.allows(pattern) else { player.requestUpgrade(.breath); return }
                            settings.routineBreathPatternID = pattern.id
                            settings.save()
                        } label: {
                            IndexRow(title: pattern.name, detail: pattern.signature, isActive: isSelected) {
                                if !pattern.isFree && !player.plan.isPlus { PlusMark() }
                            }
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }
                SettingRow(title: "For") {
                    ChoiceRow(
                        options: [(2, "2"), (3, "3"), (5, "5"), (8, "8")],
                        selection: settings.routineBreathMinutes
                    ) { choice in
                        guard editable else { player.requestUpgrade(.routine); return }
                        settings.routineBreathMinutes = choice
                        settings.save()
                    }
                    .frame(width: 190)
                }

                SectionLabel("Then play")
                    .padding(.top, 22)
                VStack(spacing: 0) {
                    Button {
                        guard editable else { player.requestUpgrade(.routine); return }
                        settings.routineMixID = nil
                        settings.save()
                    } label: {
                        IndexRow(title: "Whatever is loaded", detail: "The mix on the Tonight screen.", isActive: settings.routineMixID == nil) {
                            EmptyView()
                        }
                    }
                    .buttonStyle(.plain)
                    Hairline()
                    ForEach(player.library.allMixes) { mix in
                        Button {
                            guard editable else { player.requestUpgrade(.routine); return }
                            settings.routineMixID = mix.id
                            settings.save()
                        } label: {
                            IndexRow(title: mix.name, detail: mix.summary, isActive: settings.routineMixID == mix.id) {
                                if !mix.usesOnlyFreeSounds && !player.plan.isPlus { PlusMark() }
                            }
                        }
                        .buttonStyle(.plain)
                        Hairline()
                    }
                }

                SectionLabel("Timer")
                    .padding(.top, 22)
                SettingRow(title: "Sleep timer", detail: "Set when the sound starts.") {
                    ChoiceRow(
                        options: [(0, "Off"), (30, "30"), (45, "45"), (60, "60"), (90, "90")],
                        selection: settings.routineTimerMinutes
                    ) { choice in
                        guard editable else { player.requestUpgrade(.routine); return }
                        settings.routineTimerMinutes = choice
                        settings.save()
                    }
                    .frame(width: 210)
                }

                SoftButton(title: "Start now", systemImage: "play.fill", isProminent: true, isWide: true) {
                    dismiss()
                    player.startRoutine()
                }
                .padding(.top, 26)
                .padding(.bottom, 30)
            }
            .pageGutter()
        }
        .sheetDressing()
        .paywallHost()
    }
}
