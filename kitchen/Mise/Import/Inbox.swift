import Foundation

/// Links handed over by the share extension wait here, in the App Group
/// container, until the app is next in front.
enum Inbox {
    static let groupID = "group.dev.brettboggs.mise"

    struct Item: Codable {
        var url: URL
        var date: Date
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
