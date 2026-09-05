import Foundation

/// Flat Codable JSON in the App Group container.
///
/// Deliberately not SwiftData or Core Data: the whole data model is a handful
/// of small structs, the widget extension has to read some of it, and nothing
/// here is worth a migration story.
enum Persistence {
    static var directory: URL {
        let fm = FileManager.default
        if let shared = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupID) {
            return shared
        }
        // App Group missing (entitlement not yet provisioned). Fall back so the
        // app still runs; only the widgets lose their data.
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        let target = url(name)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("Hush: could not save \(name): \(error.localizedDescription)")
        }
    }
}
