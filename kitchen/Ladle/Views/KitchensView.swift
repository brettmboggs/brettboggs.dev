import SwiftUI

/// The kitchen name above a tab's title. Tapping it switches kitchens or
/// adds one. Shown on the tabs that change with the kitchen: Tonight,
/// Pantry, List and Plan.
struct KitchenSwitcher: View {
    @Environment(Library.self) private var library
    @State private var showManage = false
    @State private var showNew = false

    var body: some View {
        Menu {
            Section("Kitchens") {
                ForEach(library.kitchens) { kitchen in
                    Button {
                        library.switchKitchen(to: kitchen.id)
                        Haptics.tap()
                    } label: {
                        if kitchen.id == library.currentKitchen.id {
                            Label(kitchen.name, systemImage: "checkmark")
                        } else {
                            Label(kitchen.name, systemImage: kitchen.symbol)
                        }
                    }
                }
            }
            Button {
                showNew = true
            } label: {
                Label("Add a kitchen", systemImage: "plus")
            }
            Button {
                showManage = true
            } label: {
                Label("Edit kitchens", systemImage: "pencil")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: library.currentKitchen.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(library.currentKitchen.name)
                    .font(Typeface.body(14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Ink.accent.opacity(0.12)))
            .contentShape(Capsule())
        }
        .accessibilityLabel("Kitchen: \(library.currentKitchen.name)")
        .accessibilityHint("Switch kitchens or add one")
        .sheet(isPresented: $showManage) {
            NavigationStack { KitchensView() }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { KitchenEditor(kitchen: nil) }
        }
    }
}

/// Every kitchen: switch, rename, reorder, remove, add.
struct KitchensView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// False when pushed from Settings, where Back already does the job.
    var showsDone = true
    @State private var editing: Kitchen?
    @State private var showNew = false
    @State private var confirmDelete: Kitchen?

    var body: some View {
        List {
            Section {
                ForEach(library.kitchens) { kitchen in
                    HStack(spacing: 14) {
                        Button {
                            library.switchKitchen(to: kitchen.id)
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kitchen.symbol)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundStyle(Ink.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kitchen.name)
                                        .font(Typeface.body(17, weight: .medium))
                                        .foregroundStyle(Ink.ink)
                                    Text(kitchen.id == library.currentKitchen.id ? "Showing now" : "Tap to switch")
                                        .font(Typeface.body(13))
                                        .foregroundStyle(Ink.inkSoft)
                                }
                                Spacer()
                                if kitchen.id == library.currentKitchen.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Ink.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            editing = kitchen
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.ink)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Ink.paperRaised))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(kitchen.name)")
                    }
                    .frame(minHeight: 52)
                    .swipeActions(edge: .trailing) {
                        if library.kitchens.count > 1 {
                            Button(role: .destructive) {
                                confirmDelete = kitchen
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { library.moveKitchens(from: $0, to: $1) }

                Button {
                    showNew = true
                } label: {
                    Label("Add a kitchen", systemImage: "plus")
                        .font(Typeface.body(17, weight: .medium))
                }
                .frame(minHeight: 44)
            } footer: {
                Text("Each kitchen has its own pantry, shopping list and plan. Your cookbook and settings are the same everywhere.")
            }
        }
        .navigationTitle("Kitchens")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            if library.kitchens.count > 1 {
                ToolbarItem(placement: showsDone ? .topBarLeading : .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(item: $editing) { kitchen in
            NavigationStack { KitchenEditor(kitchen: kitchen) }
        }
        .sheet(isPresented: $showNew) {
            NavigationStack { KitchenEditor(kitchen: nil) }
        }
        .confirmationDialog(
            "Delete \(confirmDelete?.name ?? "this kitchen")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete kitchen", role: .destructive) {
                if let kitchen = confirmDelete { library.deleteKitchen(kitchen.id) }
                confirmDelete = nil
            }
        } message: {
            Text("Its pantry, shopping list and plan are deleted. Recipes stay in your cookbook.")
        }
    }
}

/// Name, icon and staples for a new kitchen or an existing one.
struct KitchenEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    /// Nil to make a new one.
    let kitchen: Kitchen?

    @State private var name = ""
    @State private var symbol = Kitchen.symbols[0]
    @State private var assumeStaples = true
    @State private var loaded = false

    private static let suggestions = ["Home", "Mom's", "Dad's", "Lakehouse", "Office", "Cabin", "Dorm", "Beach house"]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .font(Typeface.body(17))
                    .textInputAutocapitalization(.words)
                if kitchen == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.suggestions.filter { suggestion in
                                !library.kitchens.contains { $0.name.lowercased() == suggestion.lowercased() }
                            }, id: \.self) { suggestion in
                                Chip(title: suggestion, isSelected: name == suggestion) { name = suggestion }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Name")
            }

            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                    ForEach(Kitchen.symbols, id: \.self) { option in
                        Button {
                            symbol = option
                            Haptics.tap()
                        } label: {
                            Image(systemName: option)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(symbol == option ? Ink.onAccent : Ink.ink)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(symbol == option ? Ink.accent : Ink.paperRaised))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.replacingOccurrences(of: ".", with: " "))
                        .accessibilityAddTraits(symbol == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Toggle("Count staples as on hand", isOn: $assumeStaples)
                    .tint(Ink.accent)
            } footer: {
                Text("Turn off for a kitchen that doesn't keep the basics, like an office.")
            }
        }
        .navigationTitle(kitchen == nil ? "New kitchen" : "Edit kitchen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(kitchen == nil ? "Add" : "Save") { save() }
                    .disabled(name.isBlank)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let kitchen {
                name = kitchen.name
                symbol = kitchen.symbol
                assumeStaples = kitchen.assumeStaples
            }
        }
    }

    private func save() {
        if var existing = kitchen {
            existing.name = name
            existing.symbol = symbol
            existing.assumeStaples = assumeStaples
            library.updateKitchen(existing)
        } else {
            library.addKitchen(name: name, symbol: symbol, assumeStaples: assumeStaples)
        }
        Haptics.success()
        dismiss()
    }
}
