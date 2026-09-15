import SwiftUI

/// The front page: what is planned, what the kitchen can make, and a button
/// for when nobody can decide.
struct TonightView: View {
    @Environment(Library.self) private var library

    @State private var path = NavigationPath()
    @State private var timers = TimerCenter.shared
    @State private var showTimers = false
    @State private var showSettings = false
    @State private var addFlow: RecipesView.AddFlow?
    @State private var surpriseSpinning = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ScreenTitle(title: "Tonight", subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), showsKitchen: true)

                if !timers.timers.isEmpty {
                    Button {
                        showTimers = true
                    } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            HStack(spacing: 10) {
                                Image(systemName: "timer")
                                ForEach(timers.timers.prefix(3)) { timer in
                                    Text(timers.ringing.contains(timer.id) ? "Done" : Format.clock(timer.remaining(at: context.date)))
                                        .monospacedDigit()
                                }
                                Spacer()
                                Text(timers.timers.count == 1 ? "1 timer" : "\(timers.timers.count) timers")
                                    .foregroundStyle(Ink.inkSoft)
                            }
                            .font(Typeface.meta(13, weight: .semibold))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.paperRaised))
                    }
                    .buttonStyle(.plain)
                    .indexInsets()
                    .listRowSeparator(.hidden)
                }

                if library.recipes.isEmpty {
                    EmptyNote(
                        title: "No recipes yet",
                        message: "Scan a recipe card or save one from a website.",
                        actionTitle: "Scan a recipe"
                    ) { addFlow = .scan }
                    .indexInsets()
                } else {
                    plannedSection
                    surpriseRow
                    readySection
                    almostSection
                    useSoonSection
                    recentSection
                }
            }
            .plainList()
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showTimers = true
                    } label: {
                        Image(systemName: "timer")
                    }
                    .accessibilityLabel("Timers")
                    AddMenu { flow in addFlow = flow }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                RecipeDetailView(recipeID: id)
            }
            .sheet(isPresented: $showTimers) { TimersView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $addFlow) { flow in
                switch flow {
                case .scan: ScanView(source: .camera)
                case .photos: ScanView(source: .photos)
                case .paste: ScanView(source: .paste)
                case .web: WebImportView()
                case .write:
                    RecipeEditorView(recipe: Recipe(), isNew: true) { recipe in
                        library.save(recipe)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                surprise()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var plannedSection: some View {
        let today = library.entries(for: DayKey.today)
        let tomorrow = library.entries(for: DayKey.upcoming(2).last ?? DayKey.today)
        Section {
            if today.isEmpty && tomorrow.isEmpty {
                Text("Nothing planned for today.")
                    .font(Typeface.body(14))
                    .foregroundStyle(Ink.inkSoft)
                    .indexInsets()
                    .listRowSeparator(.hidden)
            }
            ForEach(today) { entry in
                planRow(entry, dayLabel: nil)
            }
            if today.isEmpty {
                ForEach(tomorrow) { entry in
                    planRow(entry, dayLabel: "Tomorrow")
                }
            }
        } header: {
            SectionLabel(today.isEmpty && !tomorrow.isEmpty ? "Tomorrow" : "Planned")
                .padding(.horizontal, 20)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private func planRow(_ entry: PlanEntry, dayLabel: String?) -> some View {
        if let id = entry.recipeID, let recipe = library.recipe(id) {
            NavigationLink(value: recipe.id) {
                IndexRow(title: recipe.title, subtitle: [entry.meal.title, recipe.metaLine].filter { !$0.isEmpty }.joined(separator: " · "), thumb: recipe) {
                    Button {
                        CookSession.shared.start(recipe)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(Ink.accent))
                            .foregroundStyle(Ink.onAccent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cook \(recipe.title)")
                }
            }
            .indexInsets()
        } else {
            HStack {
                Text(entry.note.isEmpty ? "Something" : entry.note)
                    .font(Typeface.body(16, weight: .medium))
                Spacer()
                Text(entry.meal.title)
                    .font(Typeface.meta(13))
                    .foregroundStyle(Ink.inkSoft)
            }
            .indexInsets()
        }
    }

    private var surpriseRow: some View {
        Button {
            surprise()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice")
                    .font(.system(size: 18, weight: .medium))
                    .rotationEffect(.degrees(surpriseSpinning ? 360 : 0))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surprise me")
                        .font(Typeface.body(16, weight: .semibold))
                    Text(library.readyToCook.isEmpty ? "Picks a random recipe. You can also shake the phone." : "Picks a recipe you can make now. You can also shake the phone.")
                        .font(Typeface.body(13))
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ink.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .indexInsets()
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var readySection: some View {
        let ready = library.readyToCook
        Section {
            if library.pantry.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your pantry is empty.")
                        .font(Typeface.body(14))
                        .foregroundStyle(Ink.inkSoft)
                    Text("Check off what you have in Pantry to see what you can make.")
                        .font(Typeface.body(14))
                        .foregroundStyle(Ink.inkSoft)
                }
                .indexInsets()
                .listRowSeparator(.hidden)
            } else if ready.isEmpty {
                Text("Nothing you can fully make yet. These are close.")
                    .font(Typeface.body(14))
                    .foregroundStyle(Ink.inkSoft)
                    .indexInsets()
                    .listRowSeparator(.hidden)
            }
            ForEach(ready.prefix(6)) { availability in
                NavigationLink(value: availability.recipe.id) {
                    IndexRow(title: availability.recipe.title, subtitle: rowSubtitle(availability), thumb: availability.recipe)
                }
                .indexInsets()
            }
            if ready.count > 6 {
                NavigationLink {
                    AvailabilityListView(title: "Ready to cook", items: ready)
                } label: {
                    Text("All \(ready.count) ready")
                        .font(Typeface.body(14, weight: .medium))
                }
                .indexInsets()
            }
        } header: {
            SectionLabel("Ready to cook", trailing: ready.isEmpty ? nil : "\(ready.count)")
                .padding(.horizontal, 20)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private var almostSection: some View {
        let almost = library.almostReady
        if !almost.isEmpty && !library.pantry.isEmpty {
            Section {
                ForEach(almost.prefix(4)) { availability in
                    NavigationLink(value: availability.recipe.id) {
                        IndexRow(title: availability.recipe.title, subtitle: availability.summary, thumb: availability.recipe)
                    }
                    .indexInsets()
                }
                if almost.count > 4 {
                    NavigationLink {
                        AvailabilityListView(title: "Missing one or two things", items: almost)
                    } label: {
                        Text("All \(almost.count)")
                            .font(Typeface.body(14, weight: .medium))
                    }
                    .indexInsets()
                }
            } header: {
                SectionLabel("Missing one or two things")
                    .padding(.horizontal, 20)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var useSoonSection: some View {
        let suggestions = library.useSoonSuggestions
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions.prefix(4), id: \.recipe.id) { suggestion in
                    NavigationLink(value: suggestion.recipe.id) {
                        IndexRow(title: suggestion.recipe.title, subtitle: "Uses " + suggestion.uses.map(\.name).joined(separator: ", "), thumb: suggestion.recipe)
                    }
                    .indexInsets()
                }
            } header: {
                SectionLabel("Use it up")
                    .padding(.horizontal, 20)
                    .textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = library.recipes.filter { $0.lastCooked != nil }.sorted { ($0.lastCooked ?? .distantPast) > ($1.lastCooked ?? .distantPast) }.prefix(4)
        if !recent.isEmpty {
            Section {
                ForEach(Array(recent)) { recipe in
                    NavigationLink(value: recipe.id) {
                        IndexRow(title: recipe.title, subtitle: recipe.lastCooked.map { "Made " + Format.relativeDay($0).lowercased() + " · " + Format.timesCooked(recipe.timesCooked).lowercased() }, thumb: recipe)
                    }
                    .indexInsets()
                }
            } header: {
                SectionLabel("Made lately")
                    .padding(.horizontal, 20)
                    .textCase(nil)
            }
        }
    }

    private func rowSubtitle(_ availability: Availability) -> String {
        var parts: [String] = []
        if !availability.recipe.metaLine.isEmpty { parts.append(availability.recipe.metaLine) }
        if !availability.substitutions.isEmpty {
            parts.append(availability.substitutions.count == 1 ? "1 swap" : "\(availability.substitutions.count) swaps")
        }
        return parts.joined(separator: " · ")
    }

    private func surprise() {
        let pool = library.readyToCook.map(\.recipe)
        let candidates = pool.isEmpty ? library.recipes : pool
        guard let pick = candidates.randomElement() else { return }
        Haptics.success()
        withAnimation(.settle) { surpriseSpinning.toggle() }
        path.append(pick.id)
    }
}

/// The full list behind a Tonight section.
struct AvailabilityListView: View {
    let title: String
    let items: [Availability]

    var body: some View {
        List {
            ForEach(items) { availability in
                NavigationLink(value: availability.recipe.id) {
                    IndexRow(title: availability.recipe.title, subtitle: availability.summary, thumb: availability.recipe)
                }
                .indexInsets()
            }
        }
        .plainList()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
