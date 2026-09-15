import SwiftUI

/// What is in the kitchen. Typed in, grouped by where it lives in the shop.
struct PantryView: View {
    @Environment(Library.self) private var library

    @State private var entry = ""
    @State private var showCommon = false
    @State private var showStaples = false
    @State private var toast: String?
    @FocusState private var entryFocused: Bool

    private var grouped: [(Aisle, [PantryItem])] {
        let groups = Dictionary(grouping: library.pantry, by: \.aisle)
        return groups.keys.sorted { $0.order < $1.order }.map { aisle in
            let items = (groups[aisle] ?? []).sorted { a, b in
                if a.useSoon != b.useSoon { return a.useSoon }
                return a.name < b.name
            }
            return (aisle, items)
        }
    }

    private var suggestions: [CatalogEntry] {
        guard entry.count >= 2 else { return [] }
        return IngredientCatalog.suggestions(matching: entry).filter { !library.hasInPantry($0.name) }
    }

    var body: some View {
        List {
            ScreenTitle(title: "Pantry", subtitle: countLine)

            HStack(spacing: 10) {
                TextField("Add what is in the kitchen", text: $entry)
                    .focused($entryFocused)
                    .submitLabel(.done)
                    .onSubmit { add(entry) }
                    .textInputAutocapitalization(.never)
                    .font(Typeface.body(16))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                if !entry.isBlank {
                    Button("Add") { add(entry) }
                        .font(Typeface.body(15, weight: .semibold))
                }
            }
            .indexInsets()
            .listRowSeparator(.hidden)

            if !suggestions.isEmpty {
                ForEach(suggestions, id: \.name) { suggestion in
                    Button {
                        add(suggestion.name)
                    } label: {
                        HStack {
                            Text(suggestion.name.capitalizedFirst())
                                .foregroundStyle(Ink.ink)
                            Spacer()
                            Text(suggestion.aisle.title)
                                .font(Typeface.meta(11))
                                .foregroundStyle(Ink.inkFaint)
                            Image(systemName: "plus")
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                    .indexInsets()
                }
            }

            if library.pantry.isEmpty {
                EmptyNote(
                    title: "An empty pantry.",
                    message: "Type things in one at a time, or start with the usual things and trim. The Tonight tab uses this to tell you what you can cook.",
                    actionTitle: "Add the usual things"
                ) { showCommon = true }
                .indexInsets()
            } else if !library.recipes.isEmpty {
                let ready = library.readyToCook.count
                let close = library.almostReady.count
                HStack(spacing: 6) {
                    PresenceDot(ready > 0 ? .have : .partial)
                    Text(readyLine(ready: ready, close: close))
                        .font(Typeface.body(14, weight: .medium))
                }
                .indexInsets()
                .listRowSeparator(.hidden)
            }

            ForEach(grouped, id: \.0) { aisle, items in
                Section {
                    ForEach(items) { item in
                        PantryRow(item: item)
                            .indexInsets()
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    library.setUseSoon(item, !item.useSoon)
                                    Haptics.tap()
                                } label: {
                                    Label(item.useSoon ? "Not soon" : "Use soon", systemImage: item.useSoon ? "clock.badge.xmark" : "clock")
                                }
                                .tint(Ink.inkSoft)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    library.removeFromPantry(item)
                                } label: {
                                    Label("Used up", systemImage: "trash")
                                }
                                Button {
                                    library.addToShopping(item.name)
                                    show("\(item.displayName) added to the list.")
                                } label: {
                                    Label("List", systemImage: "cart.badge.plus")
                                }
                                .tint(Ink.ink)
                            }
                    }
                } header: {
                    SectionLabel(aisle.title, trailing: "\(items.count)")
                        .padding(.horizontal, 20)
                        .textCase(nil)
                }
            }
        }
        .plainList()
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCommon = true } label: { Label("Add the usual things", systemImage: "basket") }
                    Button { showStaples = true } label: { Label("Staples", systemImage: "checklist.checked") }
                    if !library.pantry.isEmpty {
                        Button { entryFocused = true } label: { Label("Add an item", systemImage: "plus") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCommon) {
            CommonItemsSheet()
        }
        .sheet(isPresented: $showStaples) {
            NavigationStack {
                StaplesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showStaples = false }
                        }
                    }
            }
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

    private var countLine: String {
        let count = library.pantry.count
        if count == 0 { return "" }
        let soon = library.pantry.filter(\.useSoon).count
        var text = count == 1 ? "1 thing on hand" : "\(count) things on hand"
        if soon > 0 { text += " · \(soon) to use soon" }
        return text
    }

    private func readyLine(ready: Int, close: Int) -> String {
        var parts: [String] = []
        parts.append(ready == 1 ? "1 recipe ready to cook" : "\(ready) recipes ready to cook")
        if close > 0 { parts.append(close == 1 ? "1 close" : "\(close) close") }
        return parts.joined(separator: " · ")
    }

    private func add(_ text: String) {
        let names = text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).collapsed }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        for name in names { library.addToPantry(name) }
        entry = ""
        Haptics.tap()
    }

    private func show(_ text: String) {
        withAnimation(.settle) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.settle) { if toast == text { toast = nil } }
        }
    }
}

struct PantryRow: View {
    let item: PantryItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(Typeface.body(16))
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(Typeface.body(13))
                        .foregroundStyle(Ink.inkSoft)
                }
            }
            Spacer()
            if item.useSoon {
                Text("USE SOON")
                    .font(Typeface.meta(9, weight: .semibold))
                    .tracking(1.2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.ink, lineWidth: 1))
            }
        }
        .padding(.vertical, 4)
    }
}

/// The starting pantry, one tap each.
struct CommonItemsSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Add everything not already here") {
                        library.addToPantry(IngredientCatalog.commonKitchen)
                        Haptics.success()
                        dismiss()
                    }
                    .font(Typeface.body(15, weight: .semibold))
                } footer: {
                    Text("Or tap the ones you have.")
                }
                Section {
                    ForEach(IngredientCatalog.commonKitchen, id: \.self) { name in
                        let present = library.hasInPantry(name)
                        Button {
                            if present { library.removeFromPantry(key: name) } else { library.addToPantry(name) }
                            Haptics.tap()
                        } label: {
                            HStack {
                                Text(name.capitalizedFirst())
                                    .foregroundStyle(Ink.ink)
                                Spacer()
                                CheckCircle(isOn: present, size: 20)
                            }
                        }
                    }
                }
            }
            .navigationTitle("The usual things")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
