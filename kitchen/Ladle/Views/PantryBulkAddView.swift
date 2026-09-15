import SwiftUI
import UIKit

/// Fill the pantry without adding things one at a time: paste or type a list,
/// say it with the keyboard's microphone, or start from a kit. Everything
/// lands on a checklist first, so nothing wrong goes in unseen.
struct PantryBulkAddView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    /// Called with how many things went in.
    let onAdded: (Int) -> Void

    @State private var text = ""
    @State private var kits: Set<String> = []
    /// Keys the reader or a kit offered that were unchecked.
    @State private var unchecked: Set<String> = []
    @FocusState private var editorFocused: Bool

    /// What was typed first, in order, then each chosen kit's items.
    private var candidates: [PantryListReader.Found] {
        var result = PantryListReader.read(text)
        var seen = Set(result.map(\.key))
        for kit in PantryKits.all where kits.contains(kit.id) {
            for name in kit.items where seen.insert(name).inserted {
                let entry = IngredientCatalog.entry(for: name)
                result.append(PantryListReader.Found(key: name, name: name, aisle: entry?.aisle ?? .other, isKnown: true))
            }
        }
        return result
    }

    private var toAdd: [PantryListReader.Found] {
        candidates.filter { !unchecked.contains($0.key) && !library.hasInPantry($0.key) }
    }

    var body: some View {
        NavigationStack {
            List {
                listSection
                kitSection
                if !candidates.isEmpty { reviewSection }
            }
            .plainList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add to pantry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                let count = toAdd.count
                InkButton(title: count == 0 ? "Add to pantry" : (count == 1 ? "Add 1 thing" : "Add \(count) things")) {
                    add()
                }
                .disabled(count == 0)
                .opacity(count == 0 ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Ink.paper)
            }
        }
    }

    // MARK: - Sections

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste, type or say what you have. Commas, one per line, or just a run of words all work.")
                .font(Typeface.body(15))
                .foregroundStyle(Ink.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("eggs, milk, 2 onions, cheddar, rice…")
                        .font(Typeface.body(17))
                        .foregroundStyle(Ink.inkFaint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .font(Typeface.body(17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.paperRaised))

            HStack(spacing: 10) {
                InkButton(title: "Paste", systemImage: "doc.on.clipboard", isProminent: false, isWide: false) {
                    if let pasted = UIPasteboard.general.string, !pasted.isBlank {
                        text = text.isBlank ? pasted : text + "\n" + pasted
                        Haptics.tap()
                    }
                }
                if !text.isEmpty {
                    InkButton(title: "Clear", isProminent: false, isWide: false) {
                        text = ""
                    }
                }
                Spacer()
            }

            Label("To say it, tap the microphone on the keyboard.", systemImage: "mic")
                .font(Typeface.body(13))
                .foregroundStyle(Ink.inkSoft)
        }
        .indexInsets()
        .listRowSeparator(.hidden)
    }

    private var kitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Or start from a kit")
            Text("Adds the usual things. Uncheck anything you don't have.")
                .font(Typeface.body(13))
                .foregroundStyle(Ink.inkSoft)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(PantryKits.all) { kit in
                    KitButton(kit: kit, isOn: kits.contains(kit.id)) {
                        if kits.contains(kit.id) { kits.remove(kit.id) } else { kits.insert(kit.id) }
                        Haptics.tap()
                    }
                }
            }
        }
        .indexInsets()
        .listRowSeparator(.hidden)
    }

    private var reviewSection: some View {
        Section {
            ForEach(candidates) { found in
                let have = library.hasInPantry(found.key)
                let isOn = have || !unchecked.contains(found.key)
                Button {
                    guard !have else { return }
                    if unchecked.contains(found.key) { unchecked.remove(found.key) } else { unchecked.insert(found.key) }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 14) {
                        CheckCircle(isOn: isOn, size: 26)
                            .opacity(have ? 0.4 : 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(found.name.capitalizedFirst())
                                .font(Typeface.body(17, weight: isOn ? .medium : .regular))
                                .foregroundStyle(isOn && !have ? Ink.ink : Ink.inkSoft)
                            Text(detail(for: found, have: have))
                                .font(Typeface.body(13))
                                .foregroundStyle(found.isKnown || have ? Ink.inkSoft : Ink.accent)
                        }
                        Spacer()
                    }
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(have ? "Already on hand" : (isOn ? "Will be added" : "Will not be added"))
                .indexInsets()
            }
        } header: {
            SectionLabel("Check what's right", trailing: "\(toAdd.count) to add")
                .padding(.horizontal, 20)
                .textCase(nil)
        }
    }

    private func detail(for found: PantryListReader.Found, have: Bool) -> String {
        if have { return "Already on hand" }
        if !found.isKnown { return "Not recognized. Will be added as written." }
        if let written = found.written { return "From \u{201C}\(written)\u{201D} · \(found.aisle.title)" }
        return found.aisle.title
    }

    // MARK: - Actions

    private func add() {
        let items = toAdd
        guard !items.isEmpty else { return }
        for found in items {
            library.addToPantry(found.name, aisle: found.aisle)
        }
        Haptics.success()
        onAdded(items.count)
        dismiss()
    }
}

private struct KitButton: View {
    let kit: PantryKit
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: kit.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kit.title)
                        .font(Typeface.body(15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(kit.items.count) items")
                        .font(Typeface.meta(11))
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .foregroundStyle(isOn ? Ink.onAccent : Ink.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isOn ? Ink.accent : Ink.paperRaised))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kit.title)
        .accessibilityValue(isOn ? "Chosen" : "Not chosen")
    }
}
