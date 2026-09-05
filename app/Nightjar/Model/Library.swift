import Foundation
import Observation

/// Saved mixes. Built-in presets are constants, so only user mixes are stored.
@Observable
final class Library {
    private(set) var userMixes: [Mix] = []

    private static let filename = "mixes.json"

    static func load() -> Library {
        let library = Library()
        library.userMixes = Persistence.load([Mix].self, from: filename) ?? []
        return library
    }

    /// The user's own first, newest first, then the presets.
    var allMixes: [Mix] {
        userMixes.sorted { $0.createdAt > $1.createdAt } + Mix.presets
    }

    func mix(withID id: UUID) -> Mix? {
        allMixes.first { $0.id == id } ?? Mix.wakePresets.first { $0.id == id }
    }

    func save(_ mix: Mix) {
        if let index = userMixes.firstIndex(where: { $0.id == mix.id }) {
            userMixes[index] = mix
        } else {
            userMixes.append(mix)
        }
        persist()
    }

    func delete(_ mix: Mix) {
        guard !mix.isBuiltIn else { return }
        userMixes.removeAll { $0.id == mix.id }
        persist()
    }

    func rename(_ mix: Mix, to name: String) {
        guard let index = userMixes.firstIndex(where: { $0.id == mix.id }) else { return }
        userMixes[index].name = name
        persist()
    }

    /// "Rain 2", "Rain 3" and so on, so saving twice never collides.
    func uniqueName(basedOn candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Mix" : trimmed
        let taken = Set(allMixes.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    private func persist() {
        Persistence.save(userMixes, to: Library.filename)
    }
}
