import SwiftUI

/// The recipe page: read it, scale it, check things off, then cook.
struct RecipeDetailView: View {
    let recipeID: UUID

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var targetServings: Int?
    @State private var multiplier: Double = 1
    @State private var checked: Set<UUID> = []
    @State private var showEditor = false
    @State private var showCookLog = false
    @State private var showPlanPicker = false
    @State private var confirmDelete = false
    @State private var cardImage: UIImage?
    @State private var pdfFile: SettingsView.ExportFile?
    @State private var scanToView: ScanRef?
    @State private var toast: String?
    @State private var rendering = false

    private var recipe: Recipe? { library.recipe(recipeID) }

    var body: some View {
        Group {
            if let recipe {
                content(recipe)
            } else {
                ContentUnavailableView("This recipe is gone", systemImage: "book.closed", description: Text("It was deleted."))
            }
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .background(Ink.paper)
    }

    private func content(_ recipe: Recipe) -> some View {
        let availability = library.availability(for: recipe)
        let scale = currentScale(recipe)
        let system = library.settings.unitSystem
        let matchByID = Dictionary(uniqueKeysWithValues: availability.matches.map { ($0.id, $0) })

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let photoID = recipe.photoID {
                    StoredPhoto(id: photoID)
                        .frame(height: 280)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 18) {
                    if recipe.needsReview {
                        reviewBanner(recipe)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.title)
                            .font(Typeface.display(34))
                            .fixedSize(horizontal: false, vertical: true)
                        if !recipe.headnote.isBlank {
                            Text(recipe.headnote)
                                .font(Typeface.body(16))
                                .foregroundStyle(Ink.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        MetaText(metaLine(recipe))
                        if !recipe.tags.isEmpty {
                            Text(recipe.tags.map { $0.capitalizedFirst() }.joined(separator: " · "))
                                .font(Typeface.meta(11))
                                .foregroundStyle(Ink.inkFaint)
                        }
                    }
                    .padding(.top, recipe.photoID == nil ? 8 : 20)

                    Hairline()

                    InkButton(title: "Cook", systemImage: "play.fill") {
                        library.markReviewed(recipe.id)
                        CookSession.shared.start(recipe, scale: scale)
                    }

                    HStack(spacing: 0) {
                        IconButton(systemImage: recipe.isFavorite ? "heart.fill" : "heart", label: "Favorite", filled: recipe.isFavorite) {
                            library.toggleFavorite(recipe.id)
                            Haptics.tap()
                        }
                        Spacer()
                        IconButton(systemImage: "calendar.badge.plus", label: "Plan") {
                            showPlanPicker = true
                        }
                        Spacer()
                        IconButton(systemImage: "cart.badge.plus", label: availability.canMake ? "List" : "Shop") {
                            let added = availability.canMake ? 0 : library.addMissing(for: recipe, scale: scale)
                            if added == 0 {
                                library.addAll(for: recipe, scale: scale)
                                show("Everything added to the list.")
                            } else {
                                show(added == 1 ? "1 thing added to the list." : "\(added) things added to the list.")
                            }
                            Haptics.success()
                        }
                        Spacer()
                        shareMenu(recipe, scale: scale, system: system)
                        Spacer()
                        IconButton(systemImage: "pencil", label: "Edit") {
                            showEditor = true
                        }
                    }

                    availabilityLine(availability, recipe: recipe, scale: scale)

                    ingredientsSection(recipe, matches: matchByID, scale: scale, system: system)

                    stepsSection(recipe, system: system)

                    if !recipe.notes.isBlank {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Notes")
                            Text(recipe.notes)
                                .font(Typeface.body(15))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    cookLogSection(recipe)

                    if !recipe.scanIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("The original")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(recipe.scanIDs, id: \.self) { id in
                                        Button {
                                            scanToView = ScanRef(id: id)
                                        } label: {
                                            StoredPhoto(id: id, contentMode: .fill)
                                                .frame(width: 110, height: 140)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Ink.hairline, lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if let nutrition = recipe.nutrition, !nutrition.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("Nutrition", trailing: "per serving, as published")
                            ForEach(nutrition.rows) { row in
                                HStack {
                                    Text(row.label)
                                    Spacer()
                                    Text(row.value)
                                        .foregroundStyle(Ink.inkSoft)
                                }
                                .font(Typeface.body(14))
                                Hairline()
                            }
                        }
                    }

                    if let url = recipe.source.url {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text("See the original on \(recipe.source.label ?? url.host() ?? "the web")")
                            }
                            .font(Typeface.body(14))
                            .foregroundStyle(Ink.inkSoft)
                        }
                    }

                    Text("Added \(Format.relativeDay(recipe.createdAt).lowercased())")
                        .font(Typeface.meta(10))
                        .foregroundStyle(Ink.inkFaint)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEditor = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        let copy = library.duplicate(recipe)
                        show("Made a copy: \(copy.title)")
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    if recipe.needsReview {
                        Button { library.markReviewed(recipe.id) } label: { Label("Mark as reviewed", systemImage: "checkmark") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            RecipeEditorView(recipe: recipe, isNew: false) { updated in
                var saved = updated
                saved.needsReview = false
                library.save(saved)
                CookSession.shared.refresh(from: library)
            }
        }
        .sheet(isPresented: $showCookLog) {
            CookLogSheet(recipe: recipe)
        }
        .sheet(isPresented: $showPlanPicker) {
            PlanPickerSheet(recipe: recipe) { day in
                show("Planned for \(DayKey.title(for: day)).")
            }
        }
        .sheet(item: $scanToView) { ref in
            ScanViewer(id: ref.id)
        }
        .sheet(isPresented: Binding(get: { cardImage != nil }, set: { if !$0 { cardImage = nil } })) {
            if let cardImage {
                CardPreview(image: cardImage, title: recipe.title)
            }
        }
        .sheet(item: $pdfFile) { file in
            ExportSheet(url: file.url)
        }
        .confirmationDialog("Delete \(recipe.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                library.delete(recipe)
                dismiss()
            }
        } message: {
            Text("This cannot be undone. Share it first if you want a copy.")
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
        .overlay {
            if rendering {
                ProgressView()
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.paperRaised))
            }
        }
    }

    // MARK: - Pieces

    private func reviewBanner(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check this recipe")
                .font(Typeface.body(15, weight: .semibold))
            Text("Make sure the ingredients and steps came through right.")
                .font(Typeface.body(14))
                .foregroundStyle(Ink.inkSoft)
            HStack(spacing: 10) {
                InkButton(title: "Fix it up", systemImage: "pencil", isProminent: true, isWide: false) { showEditor = true }
                InkButton(title: "Looks right", isProminent: false, isWide: false) { library.markReviewed(recipe.id) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.paperRaised))
        .padding(.top, 16)
    }

    private func metaLine(_ recipe: Recipe) -> String {
        var parts: [String] = []
        if let prep = recipe.prepMinutes, prep > 0 { parts.append("Prep " + Format.minutes(prep)) }
        if let cook = recipe.cookMinutes, cook > 0 { parts.append("Cook " + Format.minutes(cook)) }
        if parts.isEmpty, let total = recipe.totalMinutes { parts.append(Format.minutes(total)) }
        if let yield = Format.yield(servings: recipe.servings, text: recipe.yieldText) { parts.append(yield) }
        if let label = recipe.source.label { parts.append(label) }
        return parts.joined(separator: " · ")
    }

    private func currentScale(_ recipe: Recipe) -> Double {
        if let base = recipe.servings, base > 0, let target = targetServings {
            return Double(target) / Double(base)
        }
        return multiplier
    }

    @ViewBuilder
    private func availabilityLine(_ availability: Availability, recipe: Recipe, scale: Double) -> some View {
        if availability.total > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PresenceDot(availability.canMake ? .have : (availability.isClose ? .partial : .missing))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.pantry.isEmpty && !availability.canMake ? "Check off what you have in Pantry to see what this needs." : availability.summary)
                        .font(Typeface.body(14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !availability.substitutions.isEmpty {
                        Text(availability.substitutions.count == 1 ? "1 swap suggested below." : "\(availability.substitutions.count) swaps suggested below.")
                            .font(Typeface.body(13))
                            .foregroundStyle(Ink.inkSoft)
                    }
                }
            }
        }
    }

    private func ingredientsSection(_ recipe: Recipe, matches: [UUID: IngredientMatch], scale: Double, system: UnitSystem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Ingredients", trailing: checked.isEmpty ? nil : "\(checked.count) of \(recipe.realIngredients.count) ready")

            HStack(spacing: 12) {
                if let base = recipe.servings, base > 0 {
                    HStack(spacing: 0) {
                        Button {
                            let current = targetServings ?? base
                            if current > 1 { targetServings = current - 1 }
                            Haptics.tap()
                        } label: {
                            Image(systemName: "minus").frame(width: 36, height: 34)
                        }
                        Text("Serves \(targetServings ?? base)")
                            .font(Typeface.meta(13, weight: .semibold))
                            .frame(minWidth: 84)
                        Button {
                            targetServings = (targetServings ?? base) + 1
                            Haptics.tap()
                        } label: {
                            Image(systemName: "plus").frame(width: 36, height: 34)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Ink.hairline, lineWidth: 1))
                    if let target = targetServings, target != base {
                        Button("Reset") { targetServings = nil }
                            .font(Typeface.meta(12))
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { value in
                            Chip(title: value == 0.5 ? "½×" : "\(Int(value))×", isSelected: multiplier == value) {
                                multiplier = value
                            }
                        }
                    }
                }
                Spacer()
                Picker("Units", selection: library.setting(\.unitSystem)) {
                    ForEach(UnitSystem.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            .padding(.vertical, 12)

            ForEach(recipe.ingredients) { ingredient in
                if ingredient.isHeading {
                    Text(ingredient.name)
                        .font(Typeface.body(15, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                        .padding(.top, 14)
                        .padding(.bottom, 6)
                } else {
                    IngredientRowView(
                        ingredient: ingredient,
                        match: matches[ingredient.id],
                        scale: scale,
                        system: system,
                        isChecked: checked.contains(ingredient.id)
                    ) {
                        if checked.contains(ingredient.id) { checked.remove(ingredient.id) } else { checked.insert(ingredient.id) }
                        Haptics.tap()
                    } addToList: {
                        library.addToShopping(ingredient, scale: scale, from: recipe)
                        show("\(ingredient.name.capitalizedFirst()) added to the list.")
                    }
                    Hairline()
                }
            }
        }
    }

    private func stepsSection(_ recipe: Recipe, system: UnitSystem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Method", trailing: "tap a step to cook from there")
                .padding(.bottom, 6)
            let real = recipe.realSteps
            ForEach(recipe.steps) { step in
                if step.isHeading {
                    Text(step.text)
                        .font(Typeface.body(15, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                } else if let index = real.firstIndex(where: { $0.id == step.id }) {
                    Button {
                        library.markReviewed(recipe.id)
                        CookSession.shared.start(recipe, scale: currentScale(recipe), at: index)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .font(Typeface.meta(12, weight: .semibold))
                                .foregroundStyle(Ink.inkSoft)
                                .frame(width: 26, alignment: .leading)
                            Text(QuantityText.localizeTemperatures(in: step.text, system: system))
                                .font(Typeface.body(16))
                                .foregroundStyle(Ink.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }

    private func cookLogSection(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Kitchen log", trailing: Format.timesCooked(recipe.timesCooked))
            HStack(spacing: 10) {
                InkButton(title: "Made it", systemImage: "checkmark", isProminent: false, isWide: false) {
                    showCookLog = true
                }
                if let rating = recipe.averageRating {
                    StaticStars(rating: rating)
                }
                if let last = recipe.lastCooked {
                    Text("Last \(Format.relativeDay(last).lowercased())")
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkSoft)
                }
            }
            ForEach(recipe.cookLog.sorted { $0.date > $1.date }.prefix(6)) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.relativeDay(entry.date))
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkSoft)
                        .frame(width: 92, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if entry.rating > 0 { StaticStars(rating: Double(entry.rating)) }
                        if !entry.note.isEmpty {
                            Text(entry.note)
                                .font(Typeface.body(14))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button(role: .destructive) {
                        library.deleteCookEntry(entry.id, from: recipe.id)
                    } label: {
                        Label("Remove this entry", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func shareMenu(_ recipe: Recipe, scale: Double, system: UnitSystem) -> some View {
        Menu {
            ShareLink(item: RecipeText.render(recipe, scale: scale, system: system), subject: Text(recipe.title)) {
                Label("Send as text", systemImage: "text.alignleft")
            }
            ShareLink(item: RecipeDocument(recipe: recipe), preview: SharePreview(recipe.title, image: Image(systemName: "doc.text"))) {
                Label("Send the recipe file", systemImage: "doc")
            }
            Button {
                render { cardImage = RecipeExport.image(for: recipe, system: system) }
            } label: {
                Label("Recipe card image", systemImage: "photo")
            }
            Button {
                render { pdfFile = RecipeExport.pdf(for: recipe, system: system).map { SettingsView.ExportFile(url: $0) } }
            } label: {
                Label("PDF to print", systemImage: "printer")
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Ink.paperRaised))
                    .foregroundStyle(Ink.ink)
                Text("Share")
                    .font(Typeface.meta(10))
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        .buttonStyle(.plain)
    }

    private func render(_ work: @escaping () -> Void) {
        rendering = true
        Task { @MainActor in
            work()
            rendering = false
        }
    }

    private func show(_ text: String) {
        withAnimation(.settle) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.settle) { if toast == text { toast = nil } }
        }
    }
}

struct ScanRef: Identifiable {
    let id: String
}

// MARK: - Rows and sheets

struct IngredientRowView: View {
    let ingredient: Ingredient
    let match: IngredientMatch?
    let scale: Double
    let system: UnitSystem
    let isChecked: Bool
    let toggle: () -> Void
    let addToList: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(isOn: isChecked)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    (Text(amount).font(Typeface.body(16, weight: .semibold)) + Text(amount.isEmpty ? "" : " ") + Text(ingredient.name).font(Typeface.body(16)))
                        .foregroundStyle(isChecked ? Ink.inkSoft : Ink.ink)
                        .strikethrough(isChecked, color: Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if let prep = ingredient.prep, !prep.isEmpty {
                        Text(prep + (ingredient.isOptional ? " · optional" : ""))
                            .font(Typeface.body(13))
                            .foregroundStyle(Ink.inkSoft)
                    } else if ingredient.isOptional {
                        Text("optional")
                            .font(Typeface.body(13))
                            .foregroundStyle(Ink.inkSoft)
                    }
                    if let sub = match?.substitution {
                        Text((sub.isHomemade ? "Make it: " : "Swap: ") + sub.note)
                            .font(Typeface.body(13))
                            .foregroundStyle(Ink.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let match {
                    PresenceDot(status: match.status)
                        .padding(.top, 7)
                        .accessibilityLabel(presenceLabel(match.status))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: addToList) {
                Label("Add to shopping list", systemImage: "cart.badge.plus")
            }
        }
    }

    private var amount: String {
        guard ingredient.quantity != nil || ingredient.unit != nil else { return "" }
        return QuantityText.string(quantity: ingredient.quantity, quantityMax: ingredient.quantityMax, unit: ingredient.unit, scale: scale, system: system)
    }

    private func presenceLabel(_ status: IngredientMatch.Status) -> String {
        switch status {
        case .have: return "In the pantry"
        case .staple: return "A staple"
        case .substitute: return "Substitute available"
        case .missing: return "Not in the pantry"
        }
    }
}

struct CookLogSheet: View {
    let recipe: Recipe
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var rating = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Text(recipe.title)
                    .font(Typeface.display(26))
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("How was it")
                    StarRating(rating: $rating)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Notes")
                    TextField("Less salt next time. Doubled the garlic.", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .font(Typeface.body(16))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                }
                Spacer()
                InkButton(title: "Save") {
                    library.logCook(recipe.id, rating: rating, note: note)
                    Haptics.success()
                    dismiss()
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PlanPickerSheet: View {
    let recipe: Recipe
    let onPlanned: (String) -> Void

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var meal: Meal = .dinner

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
                Section("Which day") {
                    ForEach(DayKey.upcoming(14), id: \.self) { day in
                        Button {
                            library.addPlan(dayKey: day, meal: meal, recipeID: recipe.id)
                            Haptics.success()
                            onPlanned(day)
                            dismiss()
                        } label: {
                            HStack {
                                Text(DayKey.title(for: day))
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                Text(DayKey.shortDate(for: day))
                                    .font(Typeface.meta(11))
                                    .foregroundStyle(Ink.inkSoft)
                                let existing = library.entries(for: day).filter { $0.meal == meal }
                                if !existing.isEmpty {
                                    Text("\(existing.count)")
                                        .font(Typeface.meta(11))
                                        .foregroundStyle(Ink.inkFaint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan \(recipe.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The scanned card, full screen, pinch to zoom.
struct ScanViewer: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    StoredPhoto(id: id, contentMode: .fit)
                        .frame(width: geo.size.width * zoom, height: geo.size.height * zoom)
                }
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(1, lastZoom * value.magnification), 5)
                        }
                        .onEnded { _ in lastZoom = zoom }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.settle) {
                        zoom = zoom > 1 ? 1 : 2.5
                        lastZoom = zoom
                    }
                }
            }
            .background(Ink.paper)
            .navigationTitle("The original")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The rendered card with a share button.
struct CardPreview: View {
    let image: UIImage
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
                        .padding(20)
                }
                ShareLink(item: Image(uiImage: image), preview: SharePreview(title, image: Image(uiImage: image))) {
                    HStack {
                        Spacer()
                        Label("Share the card", systemImage: "square.and.arrow.up")
                            .font(Typeface.body(16, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Ink.onAccent)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.accent))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(Ink.paperRaised)
            .navigationTitle("Recipe card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
