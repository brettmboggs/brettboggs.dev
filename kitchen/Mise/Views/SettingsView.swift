import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var exportFile: ExportFile?
    @State private var showImporter = false
    @State private var message: String?
    @State private var confirmClearPantry = false

    struct ExportFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Measurements", selection: library.setting(\.unitSystem)) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system == .us ? "Cups & ounces" : "Grams & millilitres").tag(system)
                        }
                    }
                } header: {
                    Text("Recipes")
                } footer: {
                    Text("Recipes stay as written. This only changes how amounts are shown.")
                }

                Section {
                    Toggle("Assume staples are on hand", isOn: library.setting(\.assumeStaples))
                    NavigationLink {
                        StaplesView()
                    } label: {
                        HStack {
                            Text("Staples")
                            Spacer()
                            Text("\(library.settings.staples.count)")
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                } header: {
                    Text("Pantry")
                } footer: {
                    Text("Salt, oil, flour and the like count as present without being listed in the pantry.")
                }

                Section("Cooking") {
                    Toggle("Read each step aloud", isOn: library.setting(\.readAloud))
                    Toggle("Listen for voice commands", isOn: library.setting(\.voiceOnByDefault))
                    Toggle("Keep the screen awake", isOn: library.setting(\.keepScreenAwake))
                    Toggle("Larger text while cooking", isOn: library.setting(\.largeCookText))
                }

                Section("Siri") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("With the phone across the kitchen, say:")
                            .foregroundStyle(Ink.inkSoft)
                        ForEach(["“Hey Siri, next step in Mise”", "“Hey Siri, repeat the step in Mise”", "“Hey Siri, start a timer in Mise”", "“Hey Siri, add eggs to my Mise list”", "“Hey Siri, what can I make in Mise”"], id: \.self) { phrase in
                            Text(phrase)
                        }
                    }
                    .font(Typeface.body(14))
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Export everything") {
                        exportLibrary()
                    }
                    Button("Bring in a file…") {
                        showImporter = true
                    }
                } header: {
                    Text("Your cookbook")
                } footer: {
                    Text("Export makes one file with every recipe, photo, pantry item and plan. AirDrop it to another phone, or keep it somewhere safe. Recipes shared one at a time from the Cookbook open the same way.")
                }

                Section {
                    Button("Restore the sample recipe") {
                        library.restoreSample()
                        message = "Sunday Pancakes is back in the Cookbook."
                    }
                    Button("Clear the pantry", role: .destructive) {
                        confirmClearPantry = true
                    }
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.versionLabel)
                    Link("Support", destination: URL(string: "https://brettboggs.dev/mise/")!)
                    Link("Privacy", destination: URL(string: "https://brettboggs.dev/mise/privacy/")!)
                } footer: {
                    Text("Nothing leaves the phone unless you share it. No account, no tracking.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exportFile) { file in
                ExportSheet(url: file.url)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.miseRecipe, .miseLibrary, .json, .data]) { result in
                switch result {
                case .success(let url):
                    do {
                        let outcome = try FileImporter.importFile(at: url, into: library)
                        switch outcome {
                        case .recipes(let recipes):
                            message = recipes.count == 1 ? "\(recipes[0].title) is in the Cookbook." : "\(recipes.count) recipes are in the Cookbook."
                        case .library(let recipes, let pantry):
                            message = "\(recipes) recipes and \(pantry) pantry items were brought in."
                        }
                    } catch {
                        message = error.localizedDescription
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .alert("Cookbook", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .confirmationDialog("Clear every pantry item?", isPresented: $confirmClearPantry, titleVisibility: .visible) {
                Button("Clear the pantry", role: .destructive) { library.clearPantry() }
            }
        }
    }

    private func exportLibrary() {
        let document = LibraryDocument(library: library)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(document.fileName)
        do {
            try document.data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            message = "The export could not be written."
        }
    }
}

/// A file ready to go: name, size, one share button.
struct ExportSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "doc")
                    .font(.system(size: 44, weight: .ultraLight))
                Text(url.lastPathComponent)
                    .font(Typeface.display(22))
                Text(sizeText)
                    .font(Typeface.meta(12))
                    .foregroundStyle(Ink.inkSoft)
                Text("Send it to another phone with AirDrop, or save it to Files or iCloud Drive as a backup. Opening the file on a phone with Mise brings everything in.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Ink.inkSoft)
                Spacer()
                ShareLink(item: url) {
                    HStack {
                        Spacer()
                        Label("Share the file", systemImage: "square.and.arrow.up")
                            .font(Typeface.body(16, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Ink.paper)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.ink))
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var sizeText: String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Which ingredients count as always in the kitchen.
struct StaplesView: View {
    @Environment(Library.self) private var library
    @State private var search = ""

    private var entries: [CatalogEntry] {
        let needle = search.lowercased().trimmingCharacters(in: .whitespaces)
        let all = IngredientCatalog.entries.sorted { $0.name < $1.name }
        guard !needle.isEmpty else { return all }
        return all.filter { entry in
            entry.name.contains(needle) || entry.aliases.contains { $0.contains(needle) }
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    ForEach(library.settings.staples.sorted(), id: \.self) { key in
                        Button {
                            library.toggleStaple(key)
                        } label: {
                            HStack {
                                Text(IngredientKey.displayName(for: key).capitalizedFirst())
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                        .foregroundStyle(Ink.ink)
                    }
                } header: {
                    Text("Counted as on hand")
                } footer: {
                    Text("Tap to remove. Search below to add more.")
                }
            }
            Section(search.isEmpty ? "Everything else" : "Matches") {
                ForEach(entries.filter { search.isEmpty ? !library.settings.staples.contains($0.name) : true }, id: \.name) { entry in
                    Button {
                        library.toggleStaple(entry.name)
                    } label: {
                        HStack {
                            Text(entry.name.capitalizedFirst())
                            Spacer()
                            if library.settings.staples.contains(entry.name) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .foregroundStyle(Ink.ink)
                }
            }
        }
        .searchable(text: $search, prompt: "Find an ingredient")
        .navigationTitle("Staples")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var versionLabel: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
