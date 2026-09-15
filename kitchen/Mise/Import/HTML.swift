import Foundation

/// Just enough HTML handling to read a recipe page. Regex on purpose: the
/// pages are messy, the goal is text, and a full parser is a dependency.
enum HTML {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "deg": "°",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "frac13": "⅓", "frac23": "⅔", "frac18": "⅛",
        "frac38": "⅜", "frac58": "⅝", "frac78": "⅞", "ndash": "–", "mdash": "—", "hellip": "…",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "times": "×", "eacute": "é",
        "egrave": "è", "ecirc": "ê", "ntilde": "ñ", "ccedil": "ç", "uuml": "ü", "ouml": "ö",
        "auml": "ä", "iacute": "í", "aacute": "á", "oacute": "ó", "uacute": "ú", "agrave": "à",
        "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·", "laquo": "«", "raquo": "»",
        "shy": "", "zwj": "", "zwnj": "", "thinsp": " ", "ensp": " ", "emsp": " ",
    ]

    private static let entityRegex = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);"#)

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let ns = text as NSString
        var result = text
        for match in entityRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let body = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                if let value = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
                    replacement = String(Character(scalar))
                }
            } else if body.hasPrefix("#") {
                if let value = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(value) {
                    replacement = String(Character(scalar))
                }
            } else {
                replacement = named[body.lowercased()]
            }
            if let replacement {
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }
        return result
    }

    private static let tagRegex = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let blockRegex = try! NSRegularExpression(pattern: #"<\s*(?:/\s*)?(?:p|div|br|li|ul|ol|h[1-6]|tr|td|th|section|article|header|footer|blockquote|dd|dt|figcaption|hr)\b[^>]*>"#, options: [.caseInsensitive])
    private static let scriptRegex = try! NSRegularExpression(pattern: #"<(script|style|noscript|svg|nav|iframe)\b[^>]*>.*?</\1\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let commentRegex = try! NSRegularExpression(pattern: #"<!--.*?-->"#, options: [.dotMatchesLineSeparators])

    /// Tags removed, entities decoded, whitespace collapsed.
    static func stripTags(_ html: String) -> String {
        let ns = html as NSString
        let noTags = tagRegex.stringByReplacingMatches(in: html, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return decodeEntities(noTags).collapsed
    }

    /// The page as lines of text, one per block element.
    static func textLines(from html: String) -> [String] {
        var text = html
        text = scriptRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        text = commentRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        text = blockRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "\n")
        text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        text = decodeEntities(text)
        return text
            .components(separatedBy: .newlines)
            .map { $0.collapsed }
            .filter { !$0.isEmpty }
    }

    /// The content of a `<meta property="og:title" content="...">` style tag.
    static func meta(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            #"<meta[^>]+(?:property|name)\s*=\s*["']"# + escaped + #"["'][^>]*content\s*=\s*["']([^"']*)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*(?:property|name)\s*=\s*["']"# + escaped + #"["']"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) {
                let value = (html as NSString).substring(with: match.range(at: 1))
                return decodeEntities(value).collapsed.nilIfBlank
            }
        }
        return nil
    }

    static func title(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)) else { return nil }
        return stripTags((html as NSString).substring(with: match.range(at: 1))).nilIfBlank
    }

    /// Inner text of every element carrying `itemprop="<name>"`.
    static func itemprops(_ name: String, in html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<([a-zA-Z0-9]+)[^>]*itemprop\s*=\s*["']"# + escaped + #"["'][^>]*>(.*?)</\1\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            stripTags(ns.substring(with: match.range(at: 2))).nilIfBlank
        }
    }

    /// The `<li>` texts inside the first element whose class contains `fragment`.
    static func listItems(inElementWithClassContaining fragment: String, in html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: fragment)
        let pattern = #"<(ul|ol|div|section)\b[^>]*class\s*=\s*["'][^"']*"# + escaped + #"[^"']*["'][^>]*>(.*?)</\1\s*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let liRegex = try? NSRegularExpression(pattern: #"<li\b[^>]*>(.*?)</li\s*>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        var best: [String] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: match.range(at: 2))
            let innerNS = inner as NSString
            let items = liRegex.matches(in: inner, range: NSRange(location: 0, length: innerNS.length)).compactMap {
                stripTags(innerNS.substring(with: $0.range(at: 1))).nilIfBlank
            }
            if items.count > best.count { best = items }
        }
        return best
    }
}
