import EventKit
import SwiftUI

/// The list for the store, grouped by aisle, checkable with one thumb.
struct ShoppingView: View {
    @Environment(Library.self) private var library

    @State private var entry = ""
    @State private var toast: String?
    @State private var confirmClear = false
    @State private var sending = false
    @FocusState private var entryFocused: Bool

    private var grouped: [(Aisle, [ShoppingItem])] {
        let groups = Dictionary(grouping: library.shopping.filter { !$0.isChecked }, by: \.aisle)
        return groups.keys.sorted { $0.order < $1.order }.map { aisle in
            (aisle, (groups[aisle] ?? []).sorted { $0.name < $1.name })
        }
    }

    private var checked: [ShoppingItem] {
        library.shopping.filter(\.isChecked).sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            ScreenTitle(title: "List", subtitle: countLine, showsKitchen: true)

            HStack(spacing: 10) {
                TextField("Add something", text: $entry)
                    .focused($entryFocused)
                    .submitLabel(.done)
                    .onSubmit { add() }
                    .textInputAutocapitalization(.never)
                    .font(Typeface.body(16))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.paperRaised))
                if !entry.isBlank {
                    Button("Add") { add() }
                        .font(Typeface.body(15, weight: .semibold))
                }
            }
            .indexInsets()
            .listRowSeparator(.hidden)

            if library.shopping.isEmpty {
                EmptyNote(
                    title: "Your list is empty",
                    message: "Open a recipe and tap Shop, or add something above."
                )
                .indexInsets()
            }

            ForEach(grouped, id: \.0) { aisle, items in
                Section {
                    ForEach(items) { item in
                        ShoppingRow(item: item, system: library.settings.unitSystem, recipeTitles: titles(for: item)) {
                            library.toggleChecked(item)
                            Haptics.tap()
                        }
                        .indexInsets()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                library.removeFromShopping(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SectionLabel(aisle.title, trailing: "\(items.count)")
                        .padding(.horizontal, 20)
                        .textCase(nil)
                }
            }

            if !checked.isEmpty {
                Section {
                    ForEach(checked) { item in
                        ShoppingRow(item: item, system: library.settings.unitSystem, recipeTitles: []) {
                            library.toggleChecked(item)
                        }
                        .indexInsets()
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                library.removeFromShopping(item)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        let moved = library.moveCheckedToPantry()
                        show(moved == 1 ? "1 thing moved into the pantry." : "\(moved) things moved into the pantry.")
                        Haptics.success()
                    } label: {
                        Label("Move checked items to Pantry", systemImage: "arrow.down.to.line")
                            .font(Typeface.body(15, weight: .medium))
                    }
                    .indexInsets()
                } header: {
                    SectionLabel("Checked", trailing: "\(checked.count)")
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
                    if !library.uncheckedShopping.isEmpty {
                        ShareLink(item: listText, subject: Text("Shopping list")) {
                            Label("Send as text", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            sendToReminders()
                        } label: {
                            Label("Add to Reminders", systemImage: "list.bullet.rectangle")
                        }
                        Divider()
                    }
                    if !checked.isEmpty {
                        Button {
                            library.clearChecked()
                        } label: {
                            Label("Clear checked items", systemImage: "checkmark.circle")
                        }
                    }
                    if !library.shopping.isEmpty {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Clear the whole list", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(library.shopping.isEmpty)
            }
        }
        .confirmationDialog("Clear the whole list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear it", role: .destructive) { library.clearShopping() }
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
            if sending { ProgressView() }
        }
    }

    private var countLine: String {
        let count = library.uncheckedShopping.count
        if count == 0 { return library.shopping.isEmpty ? "" : "All checked" }
        return count == 1 ? "1 thing to get" : "\(count) things to get"
    }

    private func titles(for item: ShoppingItem) -> [String] {
        item.recipeIDs.compactMap { library.recipe($0)?.title }
    }

    private var listText: String {
        var lines: [String] = ["Shopping list"]
        for (aisle, items) in grouped {
            lines.append("")
            lines.append(aisle.title.uppercased())
            for item in items {
                let amount = item.quantityText(system: library.settings.unitSystem)
                lines.append("• " + (amount.isEmpty ? item.displayName : "\(amount) \(item.name)"))
            }
        }
        return lines.joined(separator: "\n")
    }

    private func add() {
        let names = entry.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { String($0).collapsed }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        for name in names { library.addToShopping(name) }
        entry = ""
        Haptics.tap()
    }

    private func sendToReminders() {
        let items = library.uncheckedShopping
        sending = true
        Task {
            defer { sending = false }
            do {
                let count = try await RemindersExport.send(items, system: library.settings.unitSystem)
                show(count == 1 ? "1 reminder added." : "\(count) reminders added.")
                Haptics.success()
            } catch {
                show(error.localizedDescription)
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

struct ShoppingRow: View {
    let item: ShoppingItem
    let system: UnitSystem
    let recipeTitles: [String]
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 12) {
                CheckCircle(isOn: item.isChecked)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    let amount = item.quantityText(system: system)
                    (Text(amount.isEmpty ? "" : amount + " ").font(Typeface.body(16, weight: .semibold)) + Text(item.displayName).font(Typeface.body(16)))
                        .foregroundStyle(item.isChecked ? Ink.inkSoft : Ink.ink)
                        .strikethrough(item.isChecked, color: Ink.inkSoft)
                    if !item.note.isEmpty || !recipeTitles.isEmpty {
                        Text([item.note, recipeTitles.isEmpty ? "" : "for " + recipeTitles.prefix(2).joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Typeface.body(13))
                            .foregroundStyle(Ink.inkSoft)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum RemindersError: LocalizedError {
    case denied
    case noList

    var errorDescription: String? {
        switch self {
        case .denied: return "Reminders access is off. Allow it in Settings › Privacy › Reminders."
        case .noList: return "No Reminders list is set up on this phone."
        }
    }
}

/// The unchecked items, each as a reminder in the default list.
enum RemindersExport {
    static func send(_ items: [ShoppingItem], system: UnitSystem) async throws -> Int {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw RemindersError.denied }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw RemindersError.noList }
        for item in items {
            let reminder = EKReminder(eventStore: store)
            let amount = item.quantityText(system: system)
            reminder.title = amount.isEmpty ? item.displayName : "\(amount) \(item.name)"
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return items.count
    }
}
