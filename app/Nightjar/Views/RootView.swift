import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case tonight
    case sounds
    case breathe
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonight: return "Tonight"
        case .sounds: return "Sounds"
        case .breathe: return "Breathe"
        case .rest: return "Rest"
        }
    }

    var symbol: String {
        switch self {
        case .tonight: return "moon"
        case .sounds: return "waveform"
        case .breathe: return "wind"
        case .rest: return "book"
        }
    }

    /// Where the orb sits on each screen, as a fraction of the height.
    var orbCenterY: Double {
        switch self {
        case .tonight: return 0.36
        case .sounds: return 0.92
        case .breathe: return 0.30
        case .rest: return 0.96
        }
    }

    var orbIntensity: Double {
        switch self {
        case .tonight: return 1.0
        case .sounds: return 0.55
        case .breathe: return 0.42
        case .rest: return 0.45
        }
    }

    var orbRim: Double {
        switch self {
        case .tonight: return 0.16
        case .sounds: return 0.08
        case .breathe: return 0.14
        case .rest: return 0.06
        }
    }

    /// Where the screen stops being atmosphere and starts being text.
    ///
    /// Content wins over the orb, always. Below `start` the orb is veiled
    /// back towards the ground colour, reaching `strength` at `end` and
    /// holding it to the bottom of the screen. Without this the halo sits
    /// behind body copy at whatever brightness it feels like, and no amount
    /// of tone mapping makes 12pt grey on a moving glow readable.
    var veil: (start: Double, end: Double, strength: Double) {
        switch self {
        case .tonight: return (0.46, 0.64, 0.82)
        case .sounds: return (0.26, 0.46, 0.90)
        case .breathe: return (0.30, 0.42, 0.94)
        case .rest: return (0.20, 0.40, 0.92)
        }
    }
}

/// The layer between the orb and the words.
struct ContentVeil: View {
    var start: Double
    var end: Double
    var strength: Double

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Palette.ground.opacity(0), location: 0),
                .init(color: Palette.ground.opacity(0), location: start),
                .init(color: Palette.ground.opacity(strength), location: end),
                .init(color: Palette.ground.opacity(strength), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The one orb lives here, behind every tab, and moves as you do.
struct RootView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab = .tonight
    @State private var showSettings = false
    @State private var isDimmed = false
    /// Kept out of SwiftUI state on purpose: it changes on every touch move
    /// and nothing should re-render for that.
    @State private var touchClock = TouchClock()

    private final class TouchClock { var last = Date() }

    private let dimClock = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var player = player

        return ZStack {
            Palette.ground.ignoresSafeArea()

            if player.settings.hasOnboarded {
                LivingCanvas(
                    energy: player.isPlaying ? player.meterLevel : 0,
                    intensity: (isDimmed ? 0.5 : 1) * tab.orbIntensity * (player.settings.reduceGlow ? 0.6 : 1),
                    rim: isDimmed ? 0.04 : tab.orbRim,
                    centerY: tab.orbCenterY,
                    frameRate: isDimmed ? 10 : 30
                )
                .animation(.settleSlow, value: tab)
                .animation(.settleSlow, value: isDimmed)

                ContentVeil(
                    start: tab.veil.start,
                    end: tab.veil.end,
                    strength: isDimmed ? tab.veil.strength * 0.7 : tab.veil.strength
                )
                .animation(.settleSlow, value: tab)
                .animation(.settleSlow, value: isDimmed)

                content
                    .opacity(isDimmed ? 0.3 : 1)
                    .animation(.settleSlow, value: isDimmed)

                VStack {
                    Spacer()
                    TabBar(selection: $tab)
                        .opacity(isDimmed ? 0.15 : 1)
                        .animation(.settleSlow, value: isDimmed)
                }
                .ignoresSafeArea(.keyboard)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }

            if player.alarmRinging {
                AlarmOverlay()
                    .zIndex(10)
                    .transition(.opacity)
            }
        }
        .animation(.settleSlow, value: player.settings.hasOnboarded)
        .animation(.settle, value: player.alarmRinging)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in wake() }
        )
        .onReceive(dimClock) { _ in evaluateDim() }
        .paywallHost()
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: breathBinding) { session in
            BreathSessionView(session: session)
        }
        .onChange(of: scenePhase) { _, phase in
            player.scenePhaseChanged(to: phase)
            if phase == .active { wake() }
        }
        .onAppear { applyDemoStateIfNeeded() }
        .onOpenURL { url in open(url) }
        .environment(\.openSettings, OpenSettingsAction { showSettings = true })
    }

    private var content: some View {
        ZStack {
            switch tab {
            case .tonight: TonightView()
            case .sounds: SoundsView()
            case .breathe: BreatheView()
            case .rest: RestView()
            }
        }
        .transition(.opacity)
        .animation(.settle, value: tab)
    }

    /// The session cover is driven by the controller so a routine can open it
    /// from anywhere, including the bedtime schedule.
    private var breathBinding: Binding<BreathSession?> {
        Binding(
            get: { player.breath },
            set: { newValue in
                if newValue == nil { player.cancelBreath() }
            }
        )
    }

    /// Debug only. Puts the app on a known screen for the store screenshots.
    private func applyDemoStateIfNeeded() {
        #if DEBUG
        if let name = Demo.tab, let requested = Tab(rawValue: name) { tab = requested }
        if Demo.shouldPlay, !player.isPlaying { player.play() }
        if Demo.tour { runTour() }
        if let sheet = Demo.sheet {
            // Presenting straight out of onAppear races the window becoming
            // key and the sheet never arrives.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                switch sheet {
                case "paywall": player.requestUpgrade(.sound("thunderstorm"))
                case "settings": showSettings = true
                default: break
                }
            }
        }
        #endif
    }

    /// The widget and the Control Centre control both arrive here.
    ///
    /// They are deep links rather than shared App Intents on purpose: a
    /// widget extension is its own module, and giving it the intents would
    /// mean giving it the player, the catalogue and the store along with
    /// them. A URL costs one line at each end and keeps the extension empty.
    private func open(_ url: URL) {
        guard url.scheme == "slumbio" else { return }
        switch url.host {
        case "winddown":
            tab = .tonight
            player.startRoutine()
        case "play":
            tab = .tonight
            if !player.isPlaying { player.play() }
        case "breathe":
            tab = .breathe
        case "sounds":
            tab = .sounds
        case "rest":
            tab = .rest
        default:
            break
        }
        wake()
    }

    #if DEBUG
    /// The preview video, pressed by a timer instead of a thumb.
    private func runTour() {
        Task { @MainActor in
            let beats: [(Double, Tab)] = [(6.5, .breathe), (6.5, .sounds), (6.0, .rest)]
            for (wait, next) in beats {
                try? await Task.sleep(for: .seconds(wait))
                withAnimation(.settleSlow) { tab = next }
            }
            try? await Task.sleep(for: .seconds(5.5))
            withAnimation(.settleSlow) { tab = .tonight }
        }
    }
    #endif

    // MARK: - Dimming

    private func wake() {
        touchClock.last = Date()
        if isDimmed { isDimmed = false }
    }

    private func evaluateDim() {
        guard player.settings.autoDim, player.isPlaying, !player.isBreathing, !player.alarmRinging else {
            if isDimmed { isDimmed = false }
            return
        }
        let idle = Date().timeIntervalSince(touchClock.last)
        if idle > player.settings.autoDimSeconds, !isDimmed {
            isDimmed = true
        }
    }
}

extension BreathSession: Identifiable {}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.settle) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        Text(tab.title)
                            .font(Typeface.meta(10, weight: isSelected ? .semibold : .regular))
                            .tracking(0.6)
                    }
                    .foregroundStyle(isSelected ? Palette.ember : Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .background(
            Rectangle()
                .fill(Palette.ground)
                .overlay(alignment: .top) { Hairline() }
                .ignoresSafeArea(edges: .bottom)
        )
        // A list scrolled to the bottom used to slide under a translucent bar
        // and turn to mush. It now passes under a fade into the ground colour
        // and disappears cleanly.
        .background(alignment: .top) {
            LinearGradient(
                colors: [Palette.ground.opacity(0), Palette.ground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 34)
            .offset(y: -34)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Opening settings from any tab

struct OpenSettingsAction {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    func callAsFunction() { run() }
}

private struct OpenSettingsEnvironmentKey: EnvironmentKey {
    static let defaultValue = OpenSettingsAction {}
}

extension EnvironmentValues {
    var openSettings: OpenSettingsAction {
        get { self[OpenSettingsEnvironmentKey.self] }
        set { self[OpenSettingsEnvironmentKey.self] = newValue }
    }
}
