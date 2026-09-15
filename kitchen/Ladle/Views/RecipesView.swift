import SwiftUI

/// The cookbook: every recipe as an index row, with search and a few filters.
struct RecipesView: View {
    @Environment(Library.self) private var library

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var sort: Sort = .recent
    @State private var addFlow: AddFlow?
    @State private var showSettings = false
    @State private var pendingDelete: Recipe?

    enum Filter: Hashable {
        case all
        case favorites
        case ready
        case quick
        case review
        case tag(String)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Recently added"
        case alpha = "A to Z"
        case cooked = "Most cooked"
        case lastCooked = "Last cooked"
        var id: String { rawValue }
    }

    enum AddFlow: String, Identifiable {
        case scan
        case photos
        case web
        case write
        case paste
        var id: String { rawValue }
    }

    var body: some View {
        let availability = Dictionary(uniqueKeysWithValues: library.availabilities.map { ($0.id, $0) })
        let recipes = filtered(availability: availability)

        List {
            ScreenTitle(title: "Cookbook", subtitle: countLine)

            if library.recipes.isEmpty {
                EmptyNote(
                    title: "No recipes yet",
                    message: "Scan a card, save one from a website, or type one in.",
                    actionTitle: "Scan a recipe"
                ) { addFlow = .scan }
                .indexInsets()
            } else {
                filterRow
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))

                if recipes.isEmpty {
                    EmptyNote(title: "No matches.", message: emptyFilterMessage)
                        .indexInsets()
                }

                ForEach(recipes) { recipe in
                    NavigationLink(value: recipe.id) {
                        RecipeRow(recipe: recipe, availability: availability[recipe.id])
                    }
                    .indexInsets()
                    .listRowSeparatorTint(Ink.hairline)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            library.toggleFavorite(recipe.id)
                            Haptics.tap()
                        } label: {
                            Label(recipe.isFavorite ? "Unfavourite" : "Favourite", systemImage: recipe.isFavorite ? "heart.slash" : "heart")
                        }
                        .tint(Ink.inkSoft)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = recipe
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            CookSession.shared.start(recipe)
                        } label: {
                            Label("Cook", systemImage: "play")
                        }
                        .tint(Ink.ink)
                    }
                }
            }
        }
        .plainList()
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search recipes and ingredients")
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
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort")
                AddMenu { flow in addFlow = flow }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            RecipeDetailView(recipeID: id)
        }
        .sheet(item: $addFlow) { flow in
            switch flow {
            case .scan:
                ScanView(source: .camera)
            case .photos:
                ScanView(source: .photos)
            case .paste:
                ScanView(source: .paste)
            case .web:
                WebImportView()
            case .write:
                RecipeEditorView(recipe: Recipe(), isNew: true) { recipe in
                    library.save(recipe)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.title ?? "this recipe")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let recipe = pendingDelete { library.delete(recipe) }
                pendingDelete = nil
            }
        } message: {
            Text("This cannot be undone. Share it first if you want a copy.")
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "All", isSelected: filter == .all) { filter = .all }
                Chip(title: "Ready to cook", isSelected: filter == .ready, count: library.readyToCook.count) { filter = .ready }
                Chip(title: "Favourites", isSelected: filter == .favorites) { filter = .favorites }
                Chip(title: "Under 30 min", isSelected: filter == .quick) { filter = .quick }
                if library.needsReviewCount > 0 {
                    Chip(title: "To review", isSelected: filter == .review, count: library.needsReviewCount) { filter = .review }
                }
                ForEach(library.allTags.prefix(12), id: \.self) { tag in
                    Chip(title: tag.capitalizedFirst(), isSelected: filter == .tag(tag)) { filter = .tag(tag) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var countLine: String {
        let count = library.recipes.count
        switch count {
        case 0: return ""
        case 1: return "1 recipe"
        default: return "\(count) recipes"
        }
    }

    private var emptyFilterMessage: String {
        switch filter {
        case .ready: return "None you can fully make yet. Tonight shows ones that are close."
        case .favorites: return "Open a recipe and tap the heart to add it here."
        case .quick: return "No recipes take 30 minutes or less."
        case .review: return "All recipes are checked."
        case .tag(let tag): return "No recipes tagged \(tag)."
        case .all: return "Try a different word."
        }
    }

    private func filtered(availability: [UUID: Availability]) -> [Recipe] {
        var list = library.recipes
        switch filter {
        case .all: break
        case .favorites: list = list.filter(\.isFavorite)
        case .ready: list = list.filter { availability[$0.id]?.canMake == true }
        case .quick: list = list.filter(\.isQuick)
        case .review: list = list.filter(\.needsReview)
        case .tag(let tag): list = list.filter { $0.tags.map { $0.lowercased() }.contains(tag) }
        }
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !needle.isEmpty {
            let words = needle.split(separator: " ").map(String.init)
            list = list.filter { recipe in
                let haystack = recipe.searchText
                return words.allSatisfy { haystack.contains($0) }
            }
        }
        switch sort {
        case .recent:
            list.sort { $0.createdAt > $1.createdAt }
        case .alpha:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .cooked:
            list.sort { a, b in
                if a.timesCooked != b.timesCooked { return a.timesCooked > b.timesCooked }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .lastCooked:
            list.sort { ($0.lastCooked ?? .distantPast) > ($1.lastCooked ?? .distantPast) }
        }
        if filter == .ready {
            list.sort { (availability[$0.id]?.score ?? 0) > (availability[$1.id]?.score ?? 0) }
        }
        return list
    }
}

/// The plus button and its five ways in.
struct AddMenu: View {
    let choose: (RecipesView.AddFlow) -> Void

    var body: some View {
        Menu {
            Button { choose(.scan) } label: { Label("Scan a card or page", systemImage: "doc.viewfinder") }
            Button { choose(.photos) } label: { Label("Read from photos", systemImage: "photo.on.rectangle") }
            Button { choose(.web) } label: { Label("From a web link", systemImage: "link") }
            Button { choose(.paste) } label: { Label("Paste text", systemImage: "doc.on.clipboard") }
            Button { choose(.write) } label: { Label("Type it in", systemImage: "pencil") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Add a recipe")
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    let availability: Availability?

    var body: some View {
        HStack(spacing: 14) {
            RecipeThumb(recipe: recipe, side: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recipe.title)
                        .font(Typeface.display(19))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.inkSoft)
                    }
                }
                HStack(spacing: 6) {
                    if let availability {
                        PresenceDot(availability.canMake ? .have : (availability.isClose ? .partial : .missing))
                    }
                    Text(subtitle)
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkSoft)
                        .lineLimit(1)
                }
                if recipe.needsReview {
                    Text("Check")
                        .font(Typeface.body(12, weight: .semibold))
                        .foregroundStyle(Ink.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Ink.accent.opacity(0.12)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = []
        if !recipe.metaLine.isEmpty { parts.append(recipe.metaLine) }
        if let availability {
            if availability.canMake { parts.append("Ready") }
            else if availability.isClose { parts.append("\(availability.missing.count) short") }
        }
        if recipe.timesCooked > 0 { parts.append("Made \(recipe.timesCooked)×") }
        return parts.joined(separator: " · ")
    }
}
