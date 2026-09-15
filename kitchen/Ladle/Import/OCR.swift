import Foundation
import UIKit
import Vision

struct RecognizedLine {
    let text: String
    let confidence: Float
    /// Vision's normalized box: origin bottom-left, 0…1.
    let box: CGRect
}

enum OCRError: LocalizedError {
    case noImage
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .noImage: return "That image could not be read."
        case .nothingFound: return "No words were found. Try better light, or hold the phone flatter over the card."
        }
    }
}

/// On-device text recognition, in reading order.
enum OCR {
    /// Every line of text on the page, top to bottom, columns handled.
    static func recognize(_ image: UIImage) async throws -> [RecognizedLine] {
        let prepared = image.scaledDown(to: 2600)
        guard let cgImage = prepared.cgImage else { throw OCRError.noImage }
        let observations: [VNRecognizedTextObservation] = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try handler.perform([request])
            return request.results ?? []
        }.value
        let lines = observations.compactMap { observation -> RecognizedLine? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let text = best.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return RecognizedLine(text: text, confidence: best.confidence, box: observation.boundingBox)
        }
        guard !lines.isEmpty else { throw OCRError.nothingFound }
        return readingOrder(lines)
    }

    /// Recipe cards are often two columns of ingredients under a full-width
    /// title, so a plain top-to-bottom sort interleaves the columns. Lines
    /// that span the page split it into bands; inside a band, the left
    /// column is read before the right.
    static func readingOrder(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        let byTop = lines.sorted { $0.box.maxY > $1.box.maxY }
        let leftOnly = lines.filter { $0.box.maxX < 0.52 && $0.box.midX < 0.45 }
        let rightOnly = lines.filter { $0.box.minX > 0.48 && $0.box.midX > 0.55 }
        let twoColumns = leftOnly.count >= 3 && rightOnly.count >= 3 && overlapVertically(leftOnly, rightOnly)
        guard twoColumns else { return mergeSameLine(byTop) }

        var result: [RecognizedLine] = []
        var left: [RecognizedLine] = []
        var right: [RecognizedLine] = []
        func flush() {
            result += left.sorted { $0.box.maxY > $1.box.maxY }
            result += right.sorted { $0.box.maxY > $1.box.maxY }
            left = []
            right = []
        }
        for line in byTop {
            let spans = line.box.width > 0.55 || (line.box.minX < 0.4 && line.box.maxX > 0.6)
            if spans {
                flush()
                result.append(line)
            } else if line.box.midX < 0.5 {
                left.append(line)
            } else {
                right.append(line)
            }
        }
        flush()
        return result
    }

    private static func overlapVertically(_ a: [RecognizedLine], _ b: [RecognizedLine]) -> Bool {
        guard let aTop = a.map(\.box.maxY).max(), let aBottom = a.map(\.box.minY).min(),
              let bTop = b.map(\.box.maxY).max(), let bBottom = b.map(\.box.minY).min() else { return false }
        let overlap = min(aTop, bTop) - max(aBottom, bBottom)
        return overlap > 0.15
    }

    /// Two observations on the same visual line, as when a quantity and its
    /// ingredient are far apart on a typed card, are joined back together.
    private static func mergeSameLine(_ lines: [RecognizedLine]) -> [RecognizedLine] {
        var out: [RecognizedLine] = []
        for line in lines {
            if let last = out.last,
               abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5,
               line.box.minX >= last.box.minX,
               line.box.minX - last.box.maxX < 0.25 {
                let merged = RecognizedLine(
                    text: last.text + " " + line.text,
                    confidence: min(last.confidence, line.confidence),
                    box: last.box.union(line.box)
                )
                out[out.count - 1] = merged
            } else {
                out.append(line)
            }
        }
        return out
    }

    /// Runs every page and hands back the lines for the parser.
    static func lines(from images: [UIImage]) async throws -> [TextRecipeParser.Line] {
        var all: [TextRecipeParser.Line] = []
        var anyText = false
        for image in images {
            do {
                let found = try await recognize(image)
                anyText = anyText || !found.isEmpty
                all += found.map { TextRecipeParser.Line(text: $0.text, confidence: $0.confidence) }
            } catch OCRError.nothingFound {
                continue
            }
        }
        guard anyText else { throw OCRError.nothingFound }
        return all
    }
}
