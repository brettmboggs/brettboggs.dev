import Foundation

/// Turns a pasted, typed or dictated list into pantry items.
///
/// Handles the shapes people actually write: one per line, commas, bullets,
/// "eggs and milk", quantities ("2 dozen eggs", "1 gal milk"), and dictation
/// with no punctuation at all ("eggs milk butter cheddar cheese"). Nothing is
/// added from here; the result goes to a review list first.
enum PantryListReader {
    struct Found: Identifiable, Hashable {
        /// The pantry key, which is the catalog name when the catalog knows it.
        let key: String
        let name: String
        let aisle: Aisle
        /// False when the catalog does not know it and the words were kept as written.
        let isKnown: Bool
        /// The words as written, when the catalog knows them by another
        /// name ("scallions" for green onions), so the review can say so.
        var written: String? = nil

        var id: String { key }
    }

    /// Words that are about the list rather than on it.
    private static let filler: Set<String> = [
        "i", "we", "ive", "weve", "im", "have", "has", "got", "get", "there", "theres", "is", "are",
        "also", "still", "left", "just", "my", "our", "few", "couple", "lot", "lots", "plenty",
        "dozen", "fridge", "freezer", "pantry", "kitchen", "cupboard", "um", "uh", "okay", "ok",
        "gal", "gallon", "gallons", "ct", "count", "pack", "pk", "stick", "loaf", "loaves",
        "something", "stuff", "things", "thing", "too", "then", "so", "maybe", "probably",
    ]

    /// Every catalog name and alias exactly as written, lowercased, to its
    /// catalog name. Names win over another entry's alias.
    private static let literalMap: [String: String] = {
        var map: [String: String] = [:]
        for entry in IngredientCatalog.entries {
            for alias in entry.aliases where map[alias.lowercased()] == nil {
                map[alias.lowercased()] = entry.name
            }
        }
        for entry in IngredientCatalog.entries { map[entry.name.lowercased()] = entry.name }
        return map
    }()

    /// The longest catalog alias, in words, worth trying at one spot.
    private static let longestAlias = 4

    static func read(_ text: String) -> [Found] {
        var found: [Found] = []
        var seen = Set<String>()
        for piece in pieces(of: text) {
            for item in items(in: piece) where seen.insert(item.key).inserted {
                found.append(item)
            }
        }
        return found
    }

    // MARK: - Splitting

    /// Lines, commas, semicolons and bullets first, then "and" / "&" unless
    /// the whole phrase is a known name.
    static func pieces(of text: String) -> [String] {
        let rough = text
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: { "\n,;•·|/".contains($0) })
            .map { String($0).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—*▢◻☐□.:"))) }
            .filter { !$0.isEmpty }

        var result: [String] = []
        for piece in rough {
            let lower = piece.lowercased()
            let parts = lower
                .replacingOccurrences(of: " & ", with: " and ")
                .components(separatedBy: " and ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // "half and half" stays whole: "half" is not a thing on its own.
            // "salt & pepper" splits, even though the catalog knows the pair.
            let everyPartKnown = parts.count > 1 && parts.allSatisfy { !items(in: $0).isEmpty && items(in: $0).allSatisfy(\.isKnown) }
            if literalMap[lower] != nil && !everyPartKnown {
                result.append(piece)
            } else {
                result.append(contentsOf: parts)
            }
        }
        return result
    }

    // MARK: - Recognizing

    private struct Word {
        let raw: String
        let key: String
    }

    private static func words(in text: String) -> [Word] {
        let lower = text.lowercased().replacingOccurrences(of: "’", with: "'")
        var words: [Word] = []
        var current = ""
        func flush() {
            defer { current = "" }
            // A possessive is a brand, not the food: Frank's, Hellmann's.
            guard !current.hasSuffix("'s") else { return }
            current = current.replacingOccurrences(of: "'", with: "")
            guard !current.isEmpty, !filler.contains(current), !IngredientKey.effectiveStopwords.contains(current) else { return }
            words.append(Word(raw: current, key: IngredientKey.singular(current)))
        }
        // Anything but a letter ends a word, hyphens included, the same way
        // the matcher splits names.
        for ch in lower {
            if ch.isLetter || (ch == "'" && !current.isEmpty) {
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    /// One piece of the list: a single known name, or several run together
    /// by dictation, found longest-first. Words the catalog does not know
    /// stay together as one item, as written.
    static func items(in piece: String) -> [Found] {
        // A name written exactly as the catalog has it, even one made only of
        // words that are usually noise ("half and half").
        let literal = piece.lowercased().trimmingCharacters(in: .whitespaces)
        if let name = literalMap[literal] {
            return [known(name, written: literal)]
        }

        let words = words(in: piece)
        guard !words.isEmpty else { return [] }

        let whole = words.map(\.key).joined(separator: " ")
        if let name = IngredientCatalog.byAlias[whole] {
            return [known(name, written: words.map(\.raw).joined(separator: " "))]
        }

        var result: [Found] = []
        var unknown: [String] = []
        func flushUnknown() {
            guard !unknown.isEmpty else { return }
            let text = unknown.joined(separator: " ")
            unknown.removeAll()
            let key = IngredientKey.make(text)
            if let entry = IngredientCatalog.entry(for: key) {
                result.append(known(entry.name, written: text))
            } else {
                result.append(Found(key: key, name: text, aisle: IngredientKey.aisle(for: key), isKnown: false))
            }
        }

        var index = 0
        while index < words.count {
            var matched = false
            let longest = min(longestAlias, words.count - index)
            for length in stride(from: longest, through: 1, by: -1) {
                let phrase = words[index..<index + length].map(\.key).joined(separator: " ")
                if let name = IngredientCatalog.byAlias[phrase] {
                    flushUnknown()
                    result.append(known(name, written: words[index..<index + length].map(\.raw).joined(separator: " ")))
                    index += length
                    matched = true
                    break
                }
            }
            if !matched {
                unknown.append(words[index].raw)
                index += 1
            }
        }
        flushUnknown()
        return result
    }

    private static func known(_ name: String, written: String) -> Found {
        let entry = IngredientCatalog.entry(for: name)
        // Only worth showing when it is a different word, not a plural.
        let plainWritten = written.folding(options: .diacriticInsensitive, locale: nil)
        let plainName = name.folding(options: .diacriticInsensitive, locale: nil)
        let differs = IngredientKey.normalizedPhrase(plainWritten) != IngredientKey.normalizedPhrase(plainName)
            && !plainName.contains(plainWritten) && !plainWritten.contains(plainName)
        return Found(key: name, name: name, aisle: entry?.aisle ?? .other, isKnown: true, written: differs ? written : nil)
    }
}
