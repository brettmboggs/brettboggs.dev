import SwiftUI

/// The next two weeks, a line per meal. Plan it, then shop for it.
struct PlanView: View {
    @Environment(Library.self) private var library

    @State private var addingFor: DayRef?
    @State private var toast: String?

    struct DayRef: Identifiable {
        let key: String
        var id: String { key }
    }

    var body: some View {
        List {
            ScreenTitle(title: "Plan", subtitle: subtitle)

            ForEach(DayKey.upcoming(14), id: \.self) { day in
                let entries = library.entries(for: day)
                Section {
                    ForEach(entries) { entry in
                        planRow(entry)
                            .indexInsets()
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    library.removePlan(entry)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    Button {
                        addingFor = DayRef(key: day)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text(entries.isEmpty ? "Plan something" : "Add another")
                                .font(Typeface.body(14))
                        }
                        .foregroundStyle(Ink.inkSoft)
                    }
                    .indexInsets()
                    .listRowSeparator(entries.isEmpty ? .hidden : .visible)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DayKey.title(for: day))
                            .font(Typeface.display(20))
                            .foregroundStyle(Ink.ink)
                        Spacer()
                        Text(DayKey.shortDate(for: day))
                            .font(Typeface.meta(11))
                            .foregroundStyle(Ink.inkSoft)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .textCase(nil)
                }
            }
        }
        .plainList()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { id in
            RecipeDetailView(recipeID: id)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        let added = library.shopForPlan(days: 7)
                        show(added == 0 ? "You have everything for this week." : (added == 1 ? "1 thing added to the list." : "\(added) things added to the list."))
                        Haptics.success()
                    } label: {
                        Label("Shop for the next 7 days", systemImage: "cart.badge.plus")
                    }
                    Button {
                        library.clearPastPlan()
                    } label: {
                        Label("Clear past days", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $addingFor) { day in
            PlanAddSheet(dayKey: day.key)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(Typeface.body(14, weight: .medium))
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Ink.ink))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var subtitle: String {
        let planned = library.plannedRecipes(days: 7).count
        if planned == 0 { return "Nothing planned this week yet" }
        return planned == 1 ? "1 recipe planned this week" : "\(planned) recipes planned this week"
    }

    @ViewBuilder
    private func planRow(_ entry: PlanEntry) -> some View {
        if let id = entry.recipeID, let recipe = library.recipe(id) {
            NavigationLink(value: recipe.id) {
                HStack(spacing: 12) {
                    RecipeThumb(recipe: recipe, side: 44, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title)
                            .font(Typeface.body(16, weight: .medium))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(entry.meal.title)
                                .font(Typeface.meta(13))
                                .foregroundStyle(Ink.inkSoft)
                            let availability = library.availability(for: recipe)
                            if availability.total > 0 {
                                PresenceDot(availability.canMake ? .have : (availability.isClose ? .partial : .missing))
                                Text(availability.canMake ? "ready" : availability.summary.lowercased())
                                    .font(Typeface.meta(13))
                                    .foregroundStyle(Ink.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.note.isEmpty ? "Something" : entry.note)
                        .font(Typeface.body(16, weight: .medium))
                    Text(entry.meal.title)
                        .font(Typeface.meta(13))
                        .foregroundStyle(Ink.inkSoft)
                }
                Spacer()
            }
        }
    }

    private func show(_ text: String) {
        withAnimation(.settle) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.settle) { if toast == text { toast = nil } }
        }
    }
}

/// Pick a recipe for a day, or write a note in its place.
struct PlanAddSheet: View {
    let dayKey: String

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var meal: Meal = .dinner
    @State private var search = ""
    @State private var note = ""

    private var recipes: [Recipe] {
        let needle = search.lowercased().trimmingCharacters(in: .whitespaces)
        let all = library.recipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        guard !needle.isEmpty else { return all }
        return all.filter { $0.searchText.contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                Section("Or just a note") {
                    HStack {
                        TextField("Leftovers, out, Dad cooks", text: $note)
                            .onSubmit { addNote() }
                        if !note.isBlank {
                            Button("Add") { addNote() }
                                .font(Typeface.body(15, weight: .semibold))
                        }
                    }
                }
                Section("Recipes") {
                    if recipes.isEmpty {
                        Text(library.recipes.isEmpty ? "No recipes yet." : "No matches.")
                            .foregroundStyle(Ink.inkSoft)
                    }
                    ForEach(recipes) { recipe in
                        Button {
                            library.addPlan(dayKey: dayKey, meal: meal, recipeID: recipe.id)
                            Haptics.success()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                RecipeThumb(recipe: recipe, side: 40, cornerRadius: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title)
                                        .foregroundStyle(Ink.ink)
                                    if !recipe.metaLine.isEmpty {
                                        Text(recipe.metaLine)
                                            .font(Typeface.meta(11))
                                            .foregroundStyle(Ink.inkSoft)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a recipe")
            .navigationTitle(DayKey.title(for: dayKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addNote() {
        guard !note.isBlank else { return }
        library.addPlan(dayKey: dayKey, meal: meal, recipeID: nil, note: note)
        Haptics.success()
        dismiss()
    }
}
