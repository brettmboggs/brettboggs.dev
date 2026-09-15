import PhotosUI
import SwiftUI

/// Writing a recipe, fixing an import, or editing one later. The same form
/// for all three; imports arrive with the doubtful lines marked.
struct RecipeEditorView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Recipe
    let isNew: Bool
    var flaggedIngredients: Set<UUID> = []
    var flaggedSteps: Set<UUID> = []
    var warnings: [String] = []
    /// Scanned pages that will be kept with the recipe.
    var scans: [UIImage] = []
    var rawText: String = ""
    /// A photo that arrived with an import, not yet stored.
    var incomingPhoto: UIImage?
    let onSave: (Recipe) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var newPhoto: UIImage?
    @State private var removePhoto = false
    @State private var showCamera = false
    @State private var showPaste = false
    @State private var showRawText = false
    @State private var tagText: String
    @State private var sourceURLText: String
    @State private var sourceName: String
    @State private var sourceAuthor: String

    init(recipe: Recipe, isNew: Bool, flaggedIngredients: Set<UUID> = [], flaggedSteps: Set<UUID> = [], warnings: [String] = [], scans: [UIImage] = [], rawText: String = "", incomingPhoto: UIImage? = nil, onSave: @escaping (Recipe) -> Void) {
        _draft = State(initialValue: recipe)
        self.isNew = isNew
        self.flaggedIngredients = flaggedIngredients
        self.flaggedSteps = flaggedSteps
        self.warnings = warnings
        self.scans = scans
        self.rawText = rawText
        self.incomingPhoto = incomingPhoto
        self.onSave = onSave
        _tagText = State(initialValue: recipe.tags.joined(separator: ", "))
        _sourceURLText = State(initialValue: recipe.source.url?.absoluteString ?? "")
        _sourceName = State(initialValue: recipe.source.name ?? "")
        _sourceAuthor = State(initialValue: recipe.source.author ?? "")
        _newPhoto = State(initialValue: incomingPhoto)
    }

    private var isReview: Bool { !flaggedIngredients.isEmpty || !flaggedSteps.isEmpty || !warnings.isEmpty || !scans.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if isReview {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(reviewHeadline)
                                .font(Typeface.body(15, weight: .semibold))
                            ForEach(warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(Typeface.body(14))
                                    .foregroundStyle(Ink.inkSoft)
                            }
                            if !rawText.isEmpty {
                                Button("Show what was read") { showRawText = true }
                                    .font(Typeface.body(14, weight: .medium))
                            }
                        }
                        .padding(.vertical, 4)
                        if !scans.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(scans.enumerated()), id: \.offset) { _, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 90, height: 120)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }

                Section("Photo") {
                    if let preview = photoPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    } else if let id = draft.photoID, !removePhoto {
                        StoredPhoto(id: id)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(hasPhoto ? "Choose a different photo" : "Choose from Photos", systemImage: "photo")
                    }
                    if CameraPicker.isAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                    }
                    if hasPhoto {
                        Button(role: .destructive) {
                            newPhoto = nil
                            photoItem = nil
                            removePhoto = true
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                }

                Section("Name") {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .font(Typeface.display(22))
                    TextField("A line about it (optional)", text: $draft.headnote, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    ForEach($draft.ingredients) { $ingredient in
                        IngredientEditRow(ingredient: $ingredient, flagged: flaggedIngredients.contains(ingredient.id))
                    }
                    .onDelete { offsets in draft.ingredients.remove(atOffsets: offsets) }
                    .onMove { from, to in draft.ingredients.move(fromOffsets: from, toOffset: to) }
                    Button {
                        draft.ingredients.append(Ingredient(text: "", name: ""))
                    } label: {
                        Label("Add ingredient", systemImage: "plus")
                    }
                    Button {
                        draft.ingredients.append(Ingredient.heading(""))
                    } label: {
                        Label("Add a heading", systemImage: "text.alignleft")
                    }
                    Button {
                        showPaste = true
                    } label: {
                        Label("Paste a list", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    HStack {
                        Text("Ingredients")
                        Spacer()
                        EditButton()
                            .font(Typeface.body(13))
                            .textCase(nil)
                    }
                } footer: {
                    Text("One per line, the way it is written: \"2 cups flour, sifted\". Amounts are picked out for scaling automatically.")
                }

                Section {
                    ForEach($draft.steps) { $step in
                        StepEditRow(step: $step, number: stepNumber(for: step.id), flagged: flaggedSteps.contains(step.id))
                    }
                    .onDelete { offsets in draft.steps.remove(atOffsets: offsets) }
                    .onMove { from, to in draft.steps.move(fromOffsets: from, toOffset: to) }
                    Button {
                        draft.steps.append(Step(text: ""))
                    } label: {
                        Label("Add step", systemImage: "plus")
                    }
                    Button {
                        draft.steps.append(Step(text: "", isHeading: true))
                    } label: {
                        Label("Add a heading", systemImage: "text.alignleft")
                    }
                } header: {
                    Text("Method")
                }

                Section("Details") {
                    Stepper(value: servingsBinding, in: 0...100) {
                        Text(draft.servings.map { "Serves \($0)" } ?? "Servings not set")
                    }
                    TextField("Makes (e.g. 24 cookies)", text: yieldBinding)
                    HStack {
                        Text("Prep")
                        Spacer()
                        TextField("min", value: $draft.prepMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("min").foregroundStyle(Ink.inkSoft)
                    }
                    HStack {
                        Text("Cook")
                        Spacer()
                        TextField("min", value: $draft.cookMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("min").foregroundStyle(Ink.inkSoft)
                    }
                    TextField("Tags, separated by commas", text: $tagText)
                        .textInputAutocapitalization(.never)
                    if !library.allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(library.allTags.prefix(15), id: \.self) { tag in
                                    Chip(title: tag, isSelected: currentTags.contains(tag)) {
                                        toggleTag(tag)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }

                Section("Where it came from") {
                    TextField("Grandma's card, a magazine, a friend", text: $sourceName)
                    TextField("Author (optional)", text: $sourceAuthor)
                    TextField("Web address (optional)", text: $sourceURLText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Notes") {
                    TextField("Tweaks, substitutions, who loves it", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? (isReview ? "Check the recipe" : "New recipe") : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isReview ? "Save" : "Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.title.isBlank)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        newPhoto = image
                        removePhoto = false
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let image {
                        newPhoto = image
                        removePhoto = false
                    }
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showPaste) {
                PasteLinesSheet { lines in
                    for line in lines {
                        draft.ingredients.append(IngredientParser.parse(line))
                    }
                }
            }
            .sheet(isPresented: $showRawText) {
                RawTextSheet(text: rawText)
            }
        }
    }

    // MARK: - Bits

    private var reviewHeadline: String {
        let count = flaggedIngredients.count + flaggedSteps.count
        if count == 0 { return "Read it through, then save." }
        return count == 1 ? "One line to check, marked below." : "\(count) lines to check, marked below."
    }

    private var hasPhoto: Bool {
        newPhoto != nil || (draft.photoID != nil && !removePhoto)
    }

    private var photoPreview: UIImage? { newPhoto }

    private var servingsBinding: Binding<Int> {
        Binding(
            get: { draft.servings ?? 0 },
            set: { draft.servings = $0 == 0 ? nil : $0 }
        )
    }

    private var yieldBinding: Binding<String> {
        Binding(
            get: { draft.yieldText ?? "" },
            set: { draft.yieldText = $0.nilIfBlank }
        )
    }

    private var currentTags: [String] {
        tagText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    private func toggleTag(_ tag: String) {
        var tags = currentTags
        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
        tagText = tags.joined(separator: ", ")
    }

    private func stepNumber(for id: UUID) -> Int? {
        var number = 0
        for step in draft.steps {
            if step.isHeading { continue }
            number += 1
            if step.id == id { return number }
        }
        return nil
    }

    private func save() {
        var recipe = draft
        recipe.title = recipe.title.collapsed
        recipe.headnote = recipe.headnote.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.ingredients = recipe.ingredients.compactMap { row in
            if row.isHeading {
                let title = row.text.collapsed
                guard !title.isEmpty else { return nil }
                var heading = row
                heading.name = title
                heading.text = title
                return heading
            }
            let text = row.text.collapsed
            guard !text.isEmpty else { return nil }
            var parsed = IngredientParser.parse(text)
            parsed.id = row.id
            return parsed
        }
        recipe.steps = recipe.steps.compactMap { step in
            let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            var copy = step
            copy.text = text
            return copy
        }
        var seen = Set<String>()
        recipe.tags = currentTags.filter { seen.insert($0).inserted }
        recipe.source.name = sourceName.nilIfBlank
        recipe.source.author = sourceAuthor.nilIfBlank
        recipe.source.url = sourceURLText.nilIfBlank.flatMap { WebRecipeImporter.url(fromText: $0) }
        if recipe.source.url != nil && recipe.source.kind == .written { recipe.source.kind = .web }

        if let newPhoto {
            if let old = recipe.photoID { PhotoStore.delete(old) }
            recipe.photoID = PhotoStore.save(newPhoto)
        } else if removePhoto, let old = recipe.photoID {
            PhotoStore.delete(old)
            recipe.photoID = nil
        }
        if !scans.isEmpty {
            recipe.scanIDs += scans.compactMap { PhotoStore.save($0, maxDimension: 2200) }
        }
        onSave(recipe)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Rows

struct IngredientEditRow: View {
    @Binding var ingredient: Ingredient
    let flagged: Bool

    var body: some View {
        if ingredient.isHeading {
            TextField("Heading, like \"For the sauce\"", text: $ingredient.text)
                .font(Typeface.meta(12, weight: .semibold))
                .textInputAutocapitalization(.words)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    if flagged {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.top, 3)
                            .accessibilityLabel("Check this line")
                    }
                    TextField("2 cups flour, sifted", text: $ingredient.text, axis: .vertical)
                        .font(Typeface.body(16))
                }
                if !ingredient.text.isBlank {
                    Text(preview)
                        .font(Typeface.meta(10))
                        .foregroundStyle(Ink.inkFaint)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var preview: String {
        let parsed = IngredientParser.parse(ingredient.text)
        if parsed.isHeading { return "heading" }
        var parts: [String] = []
        let amount = QuantityText.string(quantity: parsed.quantity, quantityMax: parsed.quantityMax, unit: parsed.unit, scale: 1, system: .us)
        if !amount.isEmpty { parts.append(amount) }
        parts.append(parsed.name)
        if let prep = parsed.prep { parts.append(prep) }
        return parts.joined(separator: " · ")
    }
}

struct StepEditRow: View {
    @Binding var step: Step
    let number: Int?
    let flagged: Bool

    var body: some View {
        if step.isHeading {
            TextField("Heading, like \"Make the filling\"", text: $step.text)
                .font(Typeface.meta(12, weight: .semibold))
                .textInputAutocapitalization(.words)
        } else {
            HStack(alignment: .top, spacing: 10) {
                Text(number.map { String(format: "%02d", $0) } ?? "")
                    .font(Typeface.meta(12, weight: .semibold))
                    .foregroundStyle(Ink.inkSoft)
                    .frame(width: 24, alignment: .leading)
                    .padding(.top, 3)
                if flagged {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 3)
                        .accessibilityLabel("Check this step")
                }
                TextField("What to do", text: $step.text, axis: .vertical)
                    .font(Typeface.body(16))
                    .lineLimit(1...12)
            }
            .padding(.vertical, 2)
        }
    }
}

/// Several ingredients at once, one per line.
struct PasteLinesSheet: View {
    let onDone: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("One ingredient per line.")
                    .font(Typeface.body(14))
                    .foregroundStyle(Ink.inkSoft)
                TextEditor(text: $text)
                    .font(Typeface.body(16))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                    .frame(minHeight: 200)
                if UIPasteboard.general.hasStrings && text.isEmpty {
                    Button {
                        text = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("Paste from the clipboard", systemImage: "doc.on.clipboard")
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Paste ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let lines = text.components(separatedBy: .newlines).map { $0.collapsed }.filter { !$0.isEmpty }
                        onDone(lines)
                        dismiss()
                    }
                    .disabled(text.isBlank)
                }
            }
        }
    }
}

struct RawTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(Typeface.meta(13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .textSelection(.enabled)
            }
            .navigationTitle("What was read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
