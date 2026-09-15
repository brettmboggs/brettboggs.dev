import Foundation

/// Links handed over by the share extension wait here, in the App Group
/// container, until the app is next in front.
enum Inbox {
    static let groupID = "group.dev.brettboggs.ladle"

    /// The extension writes with JSONSerialization: `url` a string, `date` an
    /// ISO 8601 string. Read exactly that, and fall back to now for a date
    /// that will not parse, so a link is never dropped over its timestamp.
    struct Item: Decodable {
        var url: URL
        var date: Date

        private enum CodingKeys: String, CodingKey { case url, date }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(URL.self, forKey: .url)
            let stamp = try? container.decode(String.self, forKey: .date)
            date = stamp.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        }
    }

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Everything waiting, oldest first. The files are removed as they are
    /// read, so a failed import does not come back forever.
    static func take() -> [URL] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var items: [Item] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let item = try? JSONDecoder().decode(Item.self, from: data) {
                items.append(item)
            }
            try? FileManager.default.removeItem(at: file)
        }
        return items.sorted { $0.date < $1.date }.map(\.url)
    }
}
