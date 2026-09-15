import Foundation
import UIKit

/// Flat Codable JSON in Application Support, photos as JPEGs beside it.
///
/// Not SwiftData: the whole model is a few arrays of small structs, and a
/// folder of JSON is something that can be backed up, exported whole and
/// read by a human. Nothing leaves the phone unless she shares it.
enum Persistence {
    static var directory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ladle", isDirectory: true)
    }

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? encoder.encode(value) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(name), options: .atomic)
        } catch {
            NSLog("Ladle: could not save \(name): \(error.localizedDescription)")
        }
    }
}

/// Recipe photos and scanned cards, stored as JPEG files named by id.
enum PhotoStore {
    static var directory: URL {
        Persistence.directory.appendingPathComponent("Photos", isDirectory: true)
    }

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        return c
    }()

    static func url(for id: String) -> URL {
        directory.appendingPathComponent(id + ".jpg", isDirectory: false)
    }

    /// Stores a photo, scaled down to something a phone screen needs, and
    /// returns its id.
    @discardableResult
    static func save(_ image: UIImage, maxDimension: CGFloat = 1600, id: String = UUID().uuidString) -> String? {
        let scaled = image.scaledDown(to: maxDimension)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        return save(data: data, id: id) ? id : nil
    }

    /// Stores already-encoded image data under a given id, as when a shared
    /// recipe file arrives with its photo inside.
    @discardableResult
    static func save(data: Data, id: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: id), options: .atomic)
            cache.removeObject(forKey: id as NSString)
            return true
        } catch {
            NSLog("Ladle: could not save photo: \(error.localizedDescription)")
            return false
        }
    }

    static func data(for id: String) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    static func load(_ id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: id).path) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// A small version for rows, decoded off the main thread.
    static func thumbnail(_ id: String, side: CGFloat) async -> UIImage? {
        let key = "\(id)@\(Int(side))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let fileURL = url(for: id)
        let scale = await MainActor.run { UIScreen.main.scale }
        let pixels = side * scale
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let full = UIImage(contentsOfFile: fileURL.path) else { return nil }
            return full.preparingThumbnail(of: CGSize(width: pixels, height: pixels))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    static func delete(_ id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
        cache.removeObject(forKey: id as NSString)
    }

    static func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }
}

extension UIImage {
    /// The image with its longest side at most `maxDimension`, orientation
    /// baked in so the file reads the same everywhere.
    func scaledDown(to maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
