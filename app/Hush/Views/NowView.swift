import Combine
import SwiftUI

struct NowView: View {
    @Environment(PlayerController.self) private var player

    @State private var showTimerSheet = false
    @State private var showSettings = false
    @State private var showSave = false
    @State private var showBedside = false
    @State private var shapingSound: SoundKind?
    @State private var saveName = ""
    @State private var lastTouch = Date()
    @State private var isDimmed = false

    private var dimFactor: Double { isDimmed ? 0.34 : 1 }

    var body: some View {
        ZStack {
            BreathingBackdrop(
                level: player.meterLevel,
                isPlaying: player.isPlaying,
                intensity: isDimmed ? 0.5 : 1
            )

            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                title
                Spacer(minLength: 16)
                layers
                Spacer(minLength: 16)
                transport
            }
            .padding(.bottom, 10)
            .opacity(dimFactor)
            .animation(.settleSlow, value: isDimmed)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in wake() }
        )
        .onReceive(dimTimer) { _ in evaluateDim() }
        .sheet(isPresented: $showTimerSheet) { TimerSheet() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $shapingSound) { kind in SoundShapingSheet(kind: kind) }
        .fullScreenCover(isPresented: $showBedside) { BedsideView() }
        .alert("Save this mix", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") {
                player.saveCurrentMix(named: saveName)
                saveName = ""
            }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("It will show up under Mixes.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text("HUSH")
                .font(Typeface.meta(11, weight: .semibold))
                .tracking(3.4)
                .foregroundStyle(Palette.inkFaint)

            Spacer()

            if player.isPlaying, let remaining = player.timerRemaining {
                Text(Format.clock(remaining))
                    .font(Typeface.meta(11))
                    .foregroundStyle(Palette.ember.opacity(0.9))
                    .contentTransition(.numericText())
                    .padding(.trailing, 4)
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .pageGutter()
        .padding(.top, 4)
    }

    private var title: some View {
        VStack(spacing: 10) {
            Text(player.currentMix.isEmpty ? "Nothing yet" : player.currentMix.name)
                .font(Typeface.display(40))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)

            Text(player.currentMix.isEmpty
                 ? "Pick something from Sounds."
                 : player.currentMix.summary)
                .font(Typeface.meta(11))
                .tracking(1.1)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .pageGutter()
    }

    @ViewBuilder
    private var layers: some View {
        if player.currentMix.layers.isEmpty {
            QuietNotice(text: "No sounds in this mix.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(player.currentMix.layers) { layer in
                        layerRow(layer)
                        if layer.id != player.currentMix.layers.last?.id {
                            Hairline()
                        }
                    }
                }
                .pageGutter()
            }
            .frame(maxHeight: 260)
        }
    }

    private func layerRow(_ layer: Layer) -> some View {
        let kind = layer.kind
        let tint = kind.map { Palette.tint(for: $0.family) } ?? Palette.ember

        return VStack(spacing: 2) {
            HStack(spacing: 10) {
                PulseDot(
                    isActive: player.isPlaying && !layer.isMuted,
                    level: player.meterLevel,
                    tint: tint
                )
                Text(layer.name)
                    .font(Typeface.body(14, weight: .medium))
                    .foregroundStyle(layer.isMuted ? Palette.inkFaint : Palette.ink)
                Spacer()
                Text("\(Int(layer.level * 100))")
                    .font(Typeface.meta(10))
                    .foregroundStyle(Palette.inkFaint)
                    .monospacedDigit()
            }

            FaderBar(
                value: layer.isMuted ? 0 : layer.level,
                tint: tint,
                onChange: { player.setLevel($0, for: layer.soundID) }
            )
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                shapingSound = kind
            } label: {
                Label("Shape", systemImage: "dial.medium")
            }
            Button {
                player.toggleMute(layer.soundID)
            } label: {
                Label(layer.isMuted ? "Unmute" : "Mute",
                      systemImage: layer.isMuted ? "speaker.wave.2" : "speaker.slash")
            }
            Button(role: .destructive) {
                player.remove(soundID: layer.soundID)
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button {
                showTimerSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: player.timerEnd == nil ? "moon.zzz" : "hourglass")
                        .font(.system(size: 17, weight: .light))
                    Text(timerLabel)
                        .font(Typeface.meta(9))
                        .tracking(0.8)
                }
                .foregroundStyle(player.timerEnd == nil ? Palette.inkSoft : Palette.ember)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                player.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(player.isPlaying ? Palette.ember.opacity(0.16) : Color.clear)
                    Circle()
                        .strokeBorder(
                            player.isPlaying ? Palette.ember.opacity(0.7) : Palette.ink.opacity(0.3),
                            lineWidth: 1
                        )
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(player.isPlaying ? Palette.ember : Palette.ink)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
                .frame(width: 76, height: 76)
            }
            .buttonStyle(.plain)
            .disabled(player.currentMix.isEmpty)
            .opacity(player.currentMix.isEmpty ? 0.35 : 1)
            .animation(.settle, value: player.isPlaying)

            Button {
                showBedside = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 17, weight: .light))
                    Text("BEDSIDE")
                        .font(Typeface.meta(9))
                        .tracking(0.8)
                }
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .pageGutter()
        .overlay(alignment: .top) {
            if player.engineFailed {
                Text("Audio could not start. Check silent mode and try again.")
                    .font(Typeface.body(12))
                    .foregroundStyle(Palette.emberDeep)
                    .padding(.horizontal, 22)
                    .offset(y: -26)
            }
        }
    }

    private var timerLabel: String {
        guard let remaining = player.timerRemaining else { return "TIMER" }
        return Format.clock(remaining)
    }

    // MARK: Auto dim

    private let dimTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private func wake() {
        lastTouch = Date()
        if isDimmed { isDimmed = false }
    }

    private func evaluateDim() {
        guard player.settings.autoDim, player.isPlaying else {
            if isDimmed { isDimmed = false }
            return
        }
        let idle = Date().timeIntervalSince(lastTouch)
        isDimmed = idle > player.settings.autoDimSeconds
    }
}

// MARK: - Timer sheet

struct TimerSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    private let choices = [10, 20, 30, 45, 60, 90, 120, 480]

    var body: some View {
        SheetShell(title: "Sleep timer") {
            VStack(alignment: .leading, spacing: 22) {
                if let remaining = player.timerRemaining {
                    HStack {
                        Text(Format.clock(remaining))
                            .font(Typeface.display(34))
                            .foregroundStyle(Palette.ember)
                            .monospacedDigit()
                        Spacer()
                        SoftButton(title: "+15m") {
                            player.extendTimer(byMinutes: 15)
                        }
                        SoftButton(title: "Off") {
                            player.cancelTimer()
                            dismiss()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Duration")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                              spacing: 8) {
                        ForEach(choices, id: \.self) { minutes in
                            Button {
                                player.setTimer(minutes: minutes)
                                dismiss()
                            } label: {
                                Text(minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m")
                                    .font(Typeface.meta(14, weight: .medium))
                                    .foregroundStyle(
                                        player.settings.timerMinutes == minutes
                                            ? Palette.ground : Palette.ink
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(player.settings.timerMinutes == minutes
                                                  ? Palette.ember : Palette.raised)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("When it runs out")
                    ChoiceRow(
                        options: TimerEndAction.allCases.map { (value: $0, label: $0.title) },
                        selection: player.settings.timerEndAction
                    ) { action in
                        player.settings.timerEndAction = action
                        player.settings.save()
                    }
                    Text(player.settings.timerEndAction == .stop
                         ? "Fades out and stops."
                         : "Fades to a quiet bed and keeps going, so an alarm can still reach you.")
                        .font(Typeface.body(12))
                        .foregroundStyle(Palette.inkFaint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Fade out", trailing: "\(Int(player.settings.fadeOutMinutes)) min")
                    FaderBar(
                        value: player.settings.fadeOutMinutes / 30,
                        tint: Palette.clay,
                        onChange: { player.settings.fadeOutMinutes = max(1, ($0 * 30).rounded()) },
                        onCommit: { player.settings.save() }
                    )
                }
            }
        }
    }
}

/// Shared sheet chrome: dark ground, a title, and a scrollable body.
struct SheetShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(title)
                            .font(Typeface.display(26))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkSoft)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Palette.raised))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 22)

                    content
                }
                .pageGutter()
                .padding(.bottom, 40)
            }
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.ground)
    }
}
