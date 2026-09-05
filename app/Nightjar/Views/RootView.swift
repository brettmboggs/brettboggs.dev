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
        case .breathe: return 0.9
        case .rest: return 0.45
        }
    }

    var orbRim: Double {
        switch self {
        case .tonight: return 0.16
        case .sounds: return 0.08
        case .breathe: return 0.22
        case .rest: return 0.06
        }
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
                .fill(Palette.ground.opacity(0.88))
                .overlay(alignment: .top) { Hairline() }
                .ignoresSafeArea(edges: .bottom)
        )
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
