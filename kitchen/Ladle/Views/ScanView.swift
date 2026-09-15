import PhotosUI
import SwiftUI

/// Getting a recipe off paper: the document camera, photos already taken,
/// or text pasted from anywhere. All three end at the same review screen.
struct ScanView: View {
    enum Source {
        case camera
        case photos
        case paste
    }

    let source: Source

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .choosing
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pastedText = ""
    @State private var draft: RecipeDraft?
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var showPhotos = false

    enum Stage {
        case choosing
        case reading
        case reviewing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choosing:
                    chooser
                case .reading:
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Reading…")
                            .font(Typeface.display(22))
                        Text("The words are read on the phone. Nothing is sent anywhere.")
                            .font(Typeface.body(14))
                            .foregroundStyle(Ink.inkSoft)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .reviewing:
                    Color.clear
                }
            }
            .background(Ink.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScanner { images in
                    showCamera = false
                    read(images)
                } onCancel: {
                    showCamera = false
                    if source == .camera && stage == .choosing { dismiss() }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 6, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
                ImportReviewView(draft: draft)
            }
            .alert("Could not read that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                switch source {
                case .camera:
                    // Let the sheet finish arriving before the camera goes over it.
                    if DocumentScanner.isSupported {
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            showCamera = true
                        }
                    }
                case .photos:
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        showPhotos = true
                    }
                case .paste:
                    if pastedText.isEmpty, UIPasteboard.general.hasStrings {
                        // Only read the clipboard when she came here to paste.
                        pastedText = UIPasteboard.general.string ?? ""
                    }
                }
            }
        }
    }

    private var title: String {
        switch source {
        case .camera: return "Scan a recipe"
        case .photos: return "Read from photos"
        case .paste: return "Paste a recipe"
        }
    }

    @ViewBuilder
    private var chooser: some View {
        switch source {
        case .paste:
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste the whole thing: title, ingredients, method. It gets sorted out on the next screen.")
                    .font(Typeface.body(14))
                    .foregroundStyle(Ink.inkSoft)
                TextEditor(text: $pastedText)
                    .font(Typeface.body(15))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                InkButton(title: "Read it", systemImage: "text.viewfinder") {
                    readText(pastedText)
                }
                .disabled(pastedText.isBlank)
                .opacity(pastedText.isBlank ? 0.4 : 1)
            }
            .padding(20)
        case .camera, .photos:
            VStack(alignment: .leading, spacing: 20) {
                if !DocumentScanner.isSupported && source == .camera {
                    Text("The document camera is not available on this device. Choose photos instead.")
                        .font(Typeface.body(15))
                        .foregroundStyle(Ink.inkSoft)
                }
                Text("Handwritten cards, printed pages, screenshots of a text. Straight on and well lit is all it needs.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Ink.inkSoft)
                if DocumentScanner.isSupported {
                    InkButton(title: "Open the camera", systemImage: "doc.viewfinder") { showCamera = true }
                }
                InkButton(title: "Choose photos", systemImage: "photo.on.rectangle", isProminent: !DocumentScanner.isSupported) { showPhotos = true }
                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - Reading

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        stage = .reading
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        guard !images.isEmpty else {
            stage = .choosing
            errorMessage = "Those photos could not be opened."
            return
        }
        read(images)
    }

    private func read(_ images: [UIImage]) {
        stage = .reading
        Task {
            do {
                let lines = try await OCR.lines(from: images)
                var result = TextRecipeParser.parse(lines: lines, kind: .scanned)
                result.scans = images
                result.recipe.source = RecipeSource(kind: .scanned)
                if result.recipe.title.isEmpty && result.recipe.realIngredients.isEmpty && result.recipe.realSteps.isEmpty {
                    throw OCRError.nothingFound
                }
                stage = .reviewing
                draft = result
                Haptics.success()
            } catch {
                stage = .choosing
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }

    private func readText(_ text: String) {
        var result = TextRecipeParser.parse(text: text, kind: .written)
        if let url = WebRecipeImporter.url(fromText: text), text.collapsed.count < 200 {
            // A pasted link is a web import, not a scan.
            stage = .reading
            Task {
                do {
                    let web = try await WebRecipeImporter.importRecipe(from: url)
                    stage = .reviewing
                    draft = web
                } catch {
                    stage = .choosing
                    errorMessage = error.localizedDescription
                }
            }
            return
        }
        result.rawText = text
        stage = .reviewing
        draft = result
    }
}

/// The last look before a recipe joins the book.
struct ImportReviewView: View {
    let draft: RecipeDraft

    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RecipeEditorView(
            recipe: draft.recipe,
            isNew: true,
            flaggedIngredients: draft.flaggedIngredientIDs,
            flaggedSteps: draft.flaggedStepIDs,
            warnings: draft.warnings,
            scans: draft.scans,
            rawText: draft.rawText,
            incomingPhoto: draft.photo
        ) { recipe in
            var saved = recipe
            saved.needsReview = false
            if library.recipes.contains(where: { $0.title.lowercased() == saved.title.lowercased() && $0.id != saved.id }) {
                saved.title = library.uniqueTitle(basedOn: saved.title)
            }
            library.save(saved)
            dismiss()
        }
    }
}

/// A link, typed or pasted.
struct WebImportView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loading = false
    @State private var draft: RecipeDraft?
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste the address of a recipe page. Most sites come through with the photo, times and servings.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Ink.inkSoft)
                HStack(spacing: 10) {
                    TextField("https://…", text: $text)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { start() }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                    if UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings {
                        Button {
                            if let url = UIPasteboard.general.url {
                                text = url.absoluteString
                            } else if let string = UIPasteboard.general.string, let url = WebRecipeImporter.url(fromText: string) {
                                text = url.absoluteString
                            }
                            start()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                        }
                        .accessibilityLabel("Paste")
                    }
                }
                InkButton(title: loading ? "Reading the page…" : "Import", systemImage: loading ? nil : "arrow.down.doc") {
                    start()
                }
                .disabled(loading || text.isBlank)
                .opacity(text.isBlank ? 0.4 : 1)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Quicker next time")
                    Text("In Safari, tap the Share button on any recipe page, then Ladle. The recipe is waiting when you come back here.")
                        .font(Typeface.body(14))
                        .foregroundStyle(Ink.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                Spacer()
            }
            .padding(20)
            .background(Ink.paper)
            .navigationTitle("From the web")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $draft, onDismiss: { dismiss() }) { draft in
                ImportReviewView(draft: draft)
            }
            .alert("Could not import that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { focused = true }
        }
    }

    private func start() {
        guard !loading, let url = WebRecipeImporter.url(fromText: text) else {
            if !text.isBlank { errorMessage = WebImportError.badURL.errorDescription }
            return
        }
        loading = true
        Task {
            defer { loading = false }
            do {
                draft = try await WebRecipeImporter.importRecipe(from: url)
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}
