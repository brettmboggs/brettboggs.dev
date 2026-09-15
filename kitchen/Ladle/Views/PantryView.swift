import SwiftUI

/// What is in the kitchen, as a checklist. Every everyday ingredient is always
/// on the screen; tapping one ticks it. Nothing here needs a swipe, a long
/// press or a hidden menu to be found.
struct PantryView: View {
    @Environment(Library.self) private var library

    @State private var entry = ""
    @State private var showStaples = false
    @State private var toast: Toast?
    @FocusState private var entryFocused: Bool

    private struct Toast: Equatable {
        let id = UUID()
        let text: String
        var undo: PantryItem?
    }

    /// One line on the shelf: an everyday ingredient, or anything already in
    /// the pantry. `item` is nil when the kitchen does not have it.
    private struct Shelf: Identifiable {
        let key: String
        let name: String
        let aisle: Aisle
        let item: PantryItem?
        var id: String { key }
    }

    private var shelf: [Shelf] {
        var rows: [Shelf] = library.pantry.map { Shelf(key: $0.key, name: $0.name, aisle: $0.aisle, item: $0) }
        var seen = Set(rows.map(\.key))
        for name in IngredientCatalog.commonKitchen {
            let key = IngredientKey.make(name)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let catalogName = IngredientCatalog.entry(for: key)?.name ?? name
            rows.append(Shelf(key: key, name: catalogName, aisle: IngredientKey.aisle(for: key), item: nil))
        }
        let needle = entry.collapsed.lowercased()
        if !needle.isEmpty {
            rows = rows.filter { $0.name.lowercased().contains(needle) }
        }
        return rows
    }

    private var grouped: [(Aisle, [Shelf])] {
        let groups = Dictionary(grouping: shelf, by: \.aisle)
        return groups.keys.sorted { $0.order < $1.order }.map { aisle in
            let rows = (groups[aisle] ?? []).sorted { a, b in
                let aSoon = a.item?.useSoon ?? false
                let bSoon = b.item?.useSoon ?? false
                if aSoon != bSoon { return aSoon }
                return a.name < b.name
            }
            return (aisle, rows)
        }
    }

    /// Catalogue matches for what is being typed that are not already listed.
    private var suggestions: [CatalogEntry] {
        guard entry.collapsed.count >= 2 else { return [] }
        let listed = Set(shelf.map(\.key))
        return IngredientCatalog.suggestions(matching: entry).filter { !listed.contains(IngredientKey.make($0.name)) && !library.hasInPantry(IngredientKey.make($0.name)) }
    }

    /// The typed text, offered as its own item when nothing matches it exactly.
    private var typedItem: String? {
        let text = entry.collapsed
        guard !text.isEmpty else { return nil }
        let key = IngredientKey.make(text)
        if shelf.contains(where: { $0.key == key }) { return nil }
        if suggestions.contains(where: { IngredientKey.make($0.name) == key }) { return nil }
        return text
    }

    var body: some View {
        List {
            ScreenTitle(title: "Pantry", subtitle: countLine)

            searchField
                .indexInsets()
                .listRowSeparator(.hidden)

            if entry.isBlank {
                Text(library.pantry.isEmpty ? "Tap everything you have in the kitchen." : "Tap to tick what you have. Tap again to take it off.")
                    .font(Typeface.body(15))
                    .foregroundStyle(Ink.inkSoft)
                    .indexInsets()
                    .listRowSeparator(.hidden)

                if !library.pantry.isEmpty && !library.recipes.isEmpty {
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
            }

            if let typedItem {
                AddLine(title: "Add \u{201C}\(typedItem)\u{201D}", detail: nil) { add(typedItem) }
                    .indexInsets()
            }
            ForEach(suggestions, id: \.name) { suggestion in
                AddLine(title: suggestion.name.capitalizedFirst(), detail: suggestion.aisle.title) { add(suggestion.name) }
                    .indexInsets()
            }

            ForEach(grouped, id: \.0) { aisle, rows in
                Section {
                    ForEach(rows) { row in
                        ShelfRow(
                            name: row.name.capitalizedFirst(),
                            note: row.item?.note ?? "",
                            have: row.item != nil,
                            useSoon: row.item?.useSoon ?? false,
                            toggle: { toggle(row) },
                            toggleUseSoon: { if let item = row.item { setUseSoon(item) } },
                            addToList: { addToList(row) },
                            remove: { if let item = row.item { remove(item) } }
                        )
                        .indexInsets()
                    }
                } header: {
                    SectionLabel(aisle.title, trailing: "\(rows.filter { $0.item != nil }.count) of \(rows.count)")
                        .padding(.horizontal, 20)
                        .textCase(nil)
                }
            }

            if entry.isBlank {
                Button {
                    showStaples = true
                } label: {
                    HStack {
                        Label("Staples you always have", systemImage: "checklist.checked")
                            .font(Typeface.body(16, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Ink.inkFaint)
                    }
                    .foregroundStyle(Ink.ink)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .indexInsets()
                .padding(.top, 12)
            }
        }
        .plainList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
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
                HStack(spacing: 14) {
                    Text(toast.text)
                        .font(Typeface.body(15, weight: .medium))
                    if let item = toast.undo {
                        Button("Undo") { undo(item) }
                            .font(Typeface.body(15, weight: .bold))
                            .underline()
                    }
                }
                .foregroundStyle(Ink.paper)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Capsule().fill(Ink.ink))
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.inkSoft)
            TextField("Find or add an ingredient", text: $entry)
                .focused($entryFocused)
                .submitLabel(.done)
                .onSubmit { submit() }
                .textInputAutocapitalization(.never)
                .font(Typeface.body(17))
            if !entry.isEmpty {
                Button {
                    entry = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Ink.inkFaint)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.paperRaised))
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

    // MARK: - Actions

    private func toggle(_ row: Shelf) {
        if let item = row.item {
            remove(item)
        } else {
            library.addToPantry(row.name)
            Haptics.tap()
        }
    }

    /// Return on the keyboard adds what was typed, or ticks the one match.
    private func submit() {
        if let typedItem {
            add(typedItem)
        } else if let first = suggestions.first {
            add(first.name)
        } else if let only = shelf.first, shelf.count == 1, only.item == nil {
            toggle(only)
            entry = ""
        }
    }

    private func add(_ text: String) {
        let names = text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).collapsed }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        for name in names { library.addToPantry(name) }
        entry = ""
        Haptics.success()
        show(names.count == 1 ? "\(names[0].capitalizedFirst()) is in the pantry." : "\(names.count) things added.")
    }

    private func remove(_ item: PantryItem) {
        library.removeFromPantry(item)
        Haptics.tap()
        show("\(item.displayName) taken off.", undo: item)
    }

    private func undo(_ item: PantryItem) {
        if let added = library.addToPantry(item.name, aisle: item.aisle) {
            var restored = added
            restored.note = item.note
            restored.useSoon = item.useSoon
            library.updatePantry(restored)
        }
        Haptics.tap()
        withAnimation(.settle) { toast = nil }
    }

    private func setUseSoon(_ item: PantryItem) {
        library.setUseSoon(item, !item.useSoon)
        Haptics.tap()
        show(item.useSoon ? "\(item.displayName) is no longer marked." : "Recipes with \(item.name) will show first.")
    }

    private func addToList(_ row: Shelf) {
        library.addToShopping(row.name)
        Haptics.tap()
        show("\(row.name.capitalizedFirst()) is on the shopping list.")
    }

    private func show(_ text: String, undo: PantryItem? = nil) {
        let next = Toast(text: text, undo: undo)
        withAnimation(.settle) { toast = next }
        Task {
            try? await Task.sleep(for: .seconds(undo == nil ? 2 : 4))
            withAnimation(.settle) { if toast == next { toast = nil } }
        }
    }
}

/// A row on the pantry checklist. The whole row is the tap target; the round
/// button on the right holds the rest, for items the kitchen has.
struct ShelfRow: View {
    let name: String
    let note: String
    let have: Bool
    let useSoon: Bool
    let toggle: () -> Void
    let toggleUseSoon: () -> Void
    let addToList: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 14) {
                    CheckCircle(isOn: have, size: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(Typeface.body(17, weight: have ? .medium : .regular))
                            .foregroundStyle(have ? Ink.ink : Ink.inkSoft)
                        if have && !note.isEmpty {
                            Text(note)
                                .font(Typeface.body(13))
                                .foregroundStyle(Ink.inkSoft)
                        }
                    }
                    Spacer(minLength: 8)
                    if useSoon {
                        Text("Use soon")
                            .font(Typeface.body(13, weight: .semibold))
                            .foregroundStyle(Ink.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Ink.accent.opacity(0.12)))
                    }
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(have ? "In the kitchen" : "Not in the kitchen")
            .accessibilityHint(have ? "Double-tap to take it off" : "Double-tap to add it")
            .accessibilityAddTraits(have ? .isSelected : [])

            Menu {
                if have {
                    Button(action: toggleUseSoon) {
                        Label(useSoon ? "Don't need to use soon" : "Use soon", systemImage: useSoon ? "clock.badge.xmark" : "clock")
                    }
                }
                Button(action: addToList) {
                    Label("Add to shopping list", systemImage: "cart.badge.plus")
                }
                if have {
                    Button(role: .destructive, action: remove) {
                        Label("Take off, it's used up", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Ink.paperRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More for \(name)")
        }
    }
}

/// A line that adds one thing to the pantry: a catalogue match, or what was typed.
private struct AddLine: View {
    let title: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Ink.accent))
                Text(title)
                    .font(Typeface.body(17, weight: .medium))
                    .foregroundStyle(Ink.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Typeface.meta(11))
                        .foregroundStyle(Ink.inkFaint)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
