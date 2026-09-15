import SwiftUI

/// One step at a time, big enough to read from the counter, movable by
/// voice, by Siri, or by tapping anywhere on the screen.
struct CookView: View {
    @Environment(Library.self) private var library

    @State private var session = CookSession.shared
    @State private var voice = VoiceControl.shared
    @State private var speaker = Speaker.shared
    @State private var timers = TimerCenter.shared

    @State private var showIngredients = false
    @State private var showTimers = false
    @State private var showDone = false
    @State private var voiceOn = false
    @State private var readAloud = false
    @State private var showTapHint = true
    @State private var checked: Set<UUID> = []

    var body: some View {
        Group {
            if let recipe = session.recipe {
                content(recipe)
            } else {
                Color.clear
            }
        }
        .background(Ink.paper)
        .onAppear { begin() }
        .onDisappear { teardown() }
        .onChange(of: session.stepIndex) { _, _ in
            if readAloud { speakCurrent() }
            Haptics.step()
        }
        .sheet(isPresented: $showIngredients) {
            if let recipe = session.recipe {
                CookIngredientsSheet(recipe: recipe, scale: session.scale, system: library.settings.unitSystem, checked: $checked)
            }
        }
        .sheet(isPresented: $showTimers) {
            TimersView()
        }
        .sheet(isPresented: $showDone, onDismiss: { end() }) {
            if let recipe = session.recipe {
                CookLogSheet(recipe: recipe)
            }
        }
    }

    private func content(_ recipe: Recipe) -> some View {
        let large = library.settings.largeCookText
        let system = library.settings.unitSystem
        let stepFont = Typeface.body(large ? 32 : 26, weight: .regular)

        return VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                Button {
                    end()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Ink.paperRaised))
                }
                .accessibilityLabel("Stop cooking")
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(Typeface.display(17))
                        .lineLimit(1)
                    Text(session.steps.isEmpty ? "No steps" : "Step \(session.stepIndex + 1) of \(session.steps.count)")
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                if !timers.timers.isEmpty {
                    Button {
                        showTimers = true
                    } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                if let soonest = timers.timers.filter({ !$0.isPaused }).min(by: { $0.remaining(at: context.date) < $1.remaining(at: context.date) }) {
                                    Text(Format.clock(soonest.remaining(at: context.date)))
                                }
                            }
                            .font(Typeface.meta(13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Ink.paperRaised))
                        }
                    }
                    .accessibilityLabel("Timers")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            GeometryReader { geo in
                Rectangle()
                    .fill(Ink.hairline)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Ink.ink)
                            .frame(width: geo.size.width * session.progress)
                            .animation(.settle, value: session.progress)
                    }
            }
            .frame(height: 2)

            if let ringing = timers.timers.first(where: { timers.ringing.contains($0.id) }) {
                ringingBanner(ringing)
            }

            // The step
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let heading = session.currentHeading {
                        Text(heading.uppercased())
                            .font(Typeface.meta(11, weight: .semibold))
                            .tracking(1.6)
                            .foregroundStyle(Ink.inkSoft)
                    }
                    if let step = session.currentStep {
                        Text(QuantityText.localizeTemperatures(in: step.text, system: system))
                            .font(stepFont)
                            .lineSpacing(large ? 7 : 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(step.id)
                            .transition(.opacity)
                    } else {
                        Text("This recipe has no steps written down yet.")
                            .font(stepFont)
                            .foregroundStyle(Ink.inkSoft)
                    }

                    let mentioned = session.ingredientsForStep
                    if !mentioned.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(mentioned) { ingredient in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Circle().fill(Ink.ink).frame(width: 5, height: 5).padding(.bottom, 3)
                                    Text(IngredientLine.text(ingredient, scale: session.scale, system: system))
                                        .font(Typeface.body(large ? 20 : 17, weight: .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.paperRaised))
                    }

                    let detected = session.detectedTimers
                    if !detected.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(detected) { timer in
                                Button {
                                    startTimer(seconds: timer.seconds)
                                } label: {
                                    Label("Start \(timer.label)", systemImage: "timer")
                                        .font(Typeface.body(15, weight: .medium))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Capsule().stroke(Ink.ink, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if showTapHint && session.stepIndex == 0 && session.steps.count > 1 {
                        Text("Tap the right side of the screen for the next step, the left to go back.")
                            .font(Typeface.meta(11))
                            .foregroundStyle(Ink.inkFaint)
                            .padding(.top, 8)
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                showTapHint = false
                if point.x < UIScreen.main.bounds.width * 0.3 {
                    session.back()
                } else {
                    advance()
                }
            }
            .animation(.settle, value: session.stepIndex)

            // Voice line
            if voiceOn {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: voice.status == .listening)
                    Text(voiceStatusText)
                        .lineLimit(1)
                }
                .font(Typeface.meta(11))
                .foregroundStyle(Ink.inkSoft)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    session.back()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 64, height: 60)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Ink.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(session.isFirst)
                .opacity(session.isFirst ? 0.3 : 1)
                .accessibilityLabel("Previous step")

                Button {
                    advance()
                } label: {
                    HStack(spacing: 10) {
                        Text(session.isLast ? "Done" : "Next")
                            .font(Typeface.body(18, weight: .semibold))
                        Image(systemName: session.isLast ? "checkmark" : "arrow.right")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(Ink.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.ink))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.isLast ? "Finish" : "Next step")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            HStack(spacing: 0) {
                toolButton("list.bullet", "Ingredients", active: false) { showIngredients = true }
                Spacer()
                toolButton("timer", timers.timers.isEmpty ? "Timer" : "\(timers.timers.count) timer\(timers.timers.count == 1 ? "" : "s")", active: !timers.timers.isEmpty) { showTimers = true }
                Spacer()
                toolButton(voiceOn ? "mic.fill" : "mic", voiceOn ? "Listening" : "Voice", active: voiceOn) { toggleVoice() }
                Spacer()
                toolButton(readAloud ? "speaker.wave.2.fill" : "speaker.wave.2", "Read aloud", active: readAloud) {
                    readAloud.toggle()
                    if readAloud { speakCurrent() } else { speaker.stop() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
    }

    private func toolButton(_ symbol: String, _ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 24)
                Text(label)
                    .font(Typeface.meta(10))
            }
            .foregroundStyle(active ? Ink.ink : Ink.inkSoft)
            .frame(minWidth: 64)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func ringingBanner(_ timer: KitchenTimer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .symbolEffect(.bounce, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Time's up")
                    .font(Typeface.body(15, weight: .semibold))
                Text(timer.label)
                    .font(Typeface.meta(11))
                    .lineLimit(1)
            }
            Spacer()
            Button("+1 min") { timers.addMinute(timer.id) }
                .font(Typeface.body(14, weight: .medium))
            Button("OK") { timers.dismissRinging(timer.id) }
                .font(Typeface.body(14, weight: .semibold))
        }
        .foregroundStyle(Ink.paper)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Ink.ink)
    }

    private var voiceStatusText: String {
        switch voice.status {
        case .starting: return "Starting the microphone…"
        case .listening: return voice.lastHeard.isEmpty ? "Listening. Say “next”, “back”, “repeat”, or “start timer”." : "Heard: \(voice.lastHeard)"
        case .denied: return "Microphone or speech access was turned off in Settings."
        case .unavailable(let why): return why
        case .off: return "Voice is off."
        }
    }

    // MARK: - Actions

    private func begin() {
        UIApplication.shared.isIdleTimerDisabled = library.settings.keepScreenAwake
        readAloud = library.settings.readAloud
        voice.onCommand = { command in handle(command) }
        if library.settings.voiceOnByDefault { enableVoice() }
        if readAloud { speakCurrent() }
    }

    private func teardown() {
        UIApplication.shared.isIdleTimerDisabled = false
        speaker.stop()
        disableVoice()
    }

    private func advance() {
        if session.isLast {
            finish()
        } else {
            session.next()
        }
    }

    private func finish() {
        speaker.stop()
        Haptics.success()
        showDone = true
    }

    private func end() {
        teardown()
        session.end()
    }

    private func speakCurrent() {
        guard let text = session.spokenStep(system: library.settings.unitSystem) else { return }
        speaker.speak(text, listening: voiceOn)
    }

    private func startTimer(seconds: Int) {
        guard let recipe = session.recipe else { return }
        timers.start(seconds: seconds, label: "\(recipe.title) · step \(session.stepIndex + 1)", recipeID: recipe.id, stepIndex: session.stepIndex)
        Haptics.success()
        if voiceOn || readAloud {
            speaker.speak("\(TimerDetector.label(forSeconds: seconds)) timer started.", listening: voiceOn)
        }
    }

    private func toggleVoice() {
        if voiceOn { disableVoice() } else { enableVoice() }
    }

    private func enableVoice() {
        voiceOn = true
        voice.onCommand = { command in handle(command) }
        voice.start()
    }

    private func disableVoice() {
        guard voiceOn || voice.isListening else { return }
        voiceOn = false
        voice.stop()
    }

    private func handle(_ command: VoiceCommand) {
        switch command {
        case .next:
            advance()
        case .back:
            session.back()
        case .repeatStep, .readStep:
            speakCurrent()
        case .startTimer(let minutes):
            if let minutes {
                startTimer(seconds: minutes * 60)
            } else if let first = session.detectedTimers.first {
                startTimer(seconds: first.seconds)
            } else {
                speaker.speak("How long? Say: set a timer for ten minutes.", listening: true)
            }
        case .stopTimer:
            if let last = timers.timers.last {
                timers.stop(last.id)
                speaker.speak("Timer stopped.", listening: true)
            }
        case .ingredients:
            showIngredients.toggle()
        case .howMuch(let thing):
            if let answer = session.answer(howMuch: thing, system: library.settings.unitSystem) {
                speaker.speak(answer, listening: true)
            } else {
                speaker.speak("I do not see \(thing) in this recipe.", listening: true)
            }
        case .finish:
            finish()
        case .stopListening:
            disableVoice()
        }
    }
}

/// The ingredient list as a sheet over cook mode, tickable.
struct CookIngredientsSheet: View {
    let recipe: Recipe
    let scale: Double
    let system: UnitSystem
    @Binding var checked: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(recipe.ingredients) { ingredient in
                    if ingredient.isHeading {
                        Text(ingredient.name.uppercased())
                            .font(Typeface.meta(11, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Ink.inkSoft)
                            .listRowSeparator(.hidden)
                    } else {
                        Button {
                            if checked.contains(ingredient.id) { checked.remove(ingredient.id) } else { checked.insert(ingredient.id) }
                            Haptics.tap()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CheckCircle(isOn: checked.contains(ingredient.id))
                                    .padding(.top, 2)
                                Text(IngredientLine.text(ingredient, scale: scale, system: system))
                                    .font(Typeface.body(18))
                                    .foregroundStyle(checked.contains(ingredient.id) ? Ink.inkSoft : Ink.ink)
                                    .strikethrough(checked.contains(ingredient.id), color: Ink.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .plainList()
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
