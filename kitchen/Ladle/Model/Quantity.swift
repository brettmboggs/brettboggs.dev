import Foundation

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case us
    case metric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .us: return "US"
        case .metric: return "Metric"
        }
    }
}

// MARK: - Fractions

/// Quantities are stored as doubles and shown as the fractions a cook expects.
enum Fractions {
    private static let vulgar: [(Double, String)] = [
        (0.125, "⅛"), (0.25, "¼"), (0.333, "⅓"), (0.375, "⅜"), (0.5, "½"),
        (0.625, "⅝"), (0.667, "⅔"), (0.75, "¾"), (0.875, "⅞"),
    ]

    /// "1½", "⅓", "2", "0.4".
    static func string(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "" }
        let whole = floor(value)
        let part = value - whole
        if part < 0.04 {
            return whole == 0 ? "0" : String(Int(whole))
        }
        if part > 0.96 {
            return String(Int(whole) + 1)
        }
        for (fraction, glyph) in vulgar where abs(part - fraction) <= 0.04 {
            return whole == 0 ? glyph : "\(Int(whole))\(glyph)"
        }
        // Nothing tidy: one decimal for larger amounts, two for a small one.
        if value < 1 {
            return String(format: "%.2f", value).trimmingTrailingZeros()
        }
        return String(format: "%.1f", value).trimmingTrailingZeros()
    }

    /// Parses "1 1/2", "1½", "½", "1/2", "1.5", "3".
    static func parse(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        text = expandVulgar(text)
        let parts = text.split(separator: " ").map(String.init)
        var total = 0.0
        var found = false
        for part in parts {
            if let slash = part.firstIndex(of: "/") {
                let n = Double(part[part.startIndex..<slash])
                let d = Double(part[part.index(after: slash)...])
                guard let n, let d, d != 0 else { return nil }
                total += n / d
                found = true
            } else if let value = Double(part.replacingOccurrences(of: ",", with: ".")) {
                total += value
                found = true
            } else {
                return nil
            }
        }
        return found ? total : nil
    }

    /// "1½" → "1 1/2", "½" → "1/2", so one regex handles every form.
    static func expandVulgar(_ text: String) -> String {
        let map: [Character: String] = [
            "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
            "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6",
            "⅚": "5/6", "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
        ]
        var out = ""
        var previousWasDigit = false
        for ch in text {
            if let expanded = map[ch] {
                if previousWasDigit { out += " " }
                out += expanded
                previousWasDigit = false
            } else {
                out.append(ch)
                previousWasDigit = ch.isNumber
            }
        }
        return out
    }
}

private extension String {
    func trimmingTrailingZeros() -> String {
        guard contains(".") else { return self }
        var s = self
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// MARK: - Units

enum UnitKind {
    case volume   // base: millilitre
    case weight   // base: gram
    case count    // no conversion
}

struct UnitInfo: Hashable {
    let id: String
    let singular: String
    let plural: String
    let abbreviation: String
    let kind: UnitKind
    /// Millilitres or grams per one of this unit. 1 for counts.
    let toBase: Double
    let system: UnitSystem?

    func name(for quantity: Double?, abbreviated: Bool) -> String {
        if abbreviated, !abbreviation.isEmpty { return abbreviation }
        guard let quantity else { return plural }
        return abs(quantity - 1) < 0.001 ? singular : plural
    }

    static func == (lhs: UnitInfo, rhs: UnitInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum Units {
    static let all: [UnitInfo] = [
        UnitInfo(id: "teaspoon", singular: "teaspoon", plural: "teaspoons", abbreviation: "tsp", kind: .volume, toBase: 4.929, system: .us),
        UnitInfo(id: "tablespoon", singular: "tablespoon", plural: "tablespoons", abbreviation: "tbsp", kind: .volume, toBase: 14.787, system: .us),
        UnitInfo(id: "fluid ounce", singular: "fluid ounce", plural: "fluid ounces", abbreviation: "fl oz", kind: .volume, toBase: 29.574, system: .us),
        UnitInfo(id: "cup", singular: "cup", plural: "cups", abbreviation: "cup", kind: .volume, toBase: 236.588, system: .us),
        UnitInfo(id: "pint", singular: "pint", plural: "pints", abbreviation: "pt", kind: .volume, toBase: 473.176, system: .us),
        UnitInfo(id: "quart", singular: "quart", plural: "quarts", abbreviation: "qt", kind: .volume, toBase: 946.353, system: .us),
        UnitInfo(id: "gallon", singular: "gallon", plural: "gallons", abbreviation: "gal", kind: .volume, toBase: 3785.41, system: .us),
        UnitInfo(id: "milliliter", singular: "millilitre", plural: "millilitres", abbreviation: "ml", kind: .volume, toBase: 1, system: .metric),
        UnitInfo(id: "liter", singular: "litre", plural: "litres", abbreviation: "l", kind: .volume, toBase: 1000, system: .metric),
        UnitInfo(id: "ounce", singular: "ounce", plural: "ounces", abbreviation: "oz", kind: .weight, toBase: 28.3495, system: .us),
        UnitInfo(id: "pound", singular: "pound", plural: "pounds", abbreviation: "lb", kind: .weight, toBase: 453.592, system: .us),
        UnitInfo(id: "gram", singular: "gram", plural: "grams", abbreviation: "g", kind: .weight, toBase: 1, system: .metric),
        UnitInfo(id: "kilogram", singular: "kilogram", plural: "kilograms", abbreviation: "kg", kind: .weight, toBase: 1000, system: .metric),
        UnitInfo(id: "pinch", singular: "pinch", plural: "pinches", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "dash", singular: "dash", plural: "dashes", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "splash", singular: "splash", plural: "splashes", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "handful", singular: "handful", plural: "handfuls", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "clove", singular: "clove", plural: "cloves", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "stick", singular: "stick", plural: "sticks", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "can", singular: "can", plural: "cans", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "jar", singular: "jar", plural: "jars", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "package", singular: "package", plural: "packages", abbreviation: "pkg", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "bag", singular: "bag", plural: "bags", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "box", singular: "box", plural: "boxes", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "bottle", singular: "bottle", plural: "bottles", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "bunch", singular: "bunch", plural: "bunches", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "sprig", singular: "sprig", plural: "sprigs", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "slice", singular: "slice", plural: "slices", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "piece", singular: "piece", plural: "pieces", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "head", singular: "head", plural: "heads", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "stalk", singular: "stalk", plural: "stalks", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "leaf", singular: "leaf", plural: "leaves", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "sheet", singular: "sheet", plural: "sheets", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "envelope", singular: "envelope", plural: "envelopes", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "drop", singular: "drop", plural: "drops", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "scoop", singular: "scoop", plural: "scoops", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "dozen", singular: "dozen", plural: "dozen", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "fillet", singular: "fillet", plural: "fillets", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "ear", singular: "ear", plural: "ears", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "rib", singular: "rib", plural: "ribs", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "square", singular: "square", plural: "squares", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "strip", singular: "strip", plural: "strips", abbreviation: "", kind: .count, toBase: 1, system: nil),
        UnitInfo(id: "wedge", singular: "wedge", plural: "wedges", abbreviation: "", kind: .count, toBase: 1, system: nil),
    ]

    private static let byID: [String: UnitInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Every spelling that means each unit, lowercase, without a trailing dot.
    private static let aliases: [String: String] = {
        var map: [String: String] = [:]
        func add(_ id: String, _ names: [String]) {
            for name in names { map[name] = id }
        }
        for unit in all {
            add(unit.id, [unit.id, unit.singular, unit.plural])
            if !unit.abbreviation.isEmpty { add(unit.id, [unit.abbreviation]) }
        }
        add("teaspoon", ["t", "tsp", "tsps", "teasp", "teaspoonful", "teaspoonfuls"])
        add("tablespoon", ["T", "tbs", "tbsp", "tbsps", "tblsp", "tablespoonful", "tablespoonfuls"])
        add("fluid ounce", ["fl oz", "fl. oz", "floz", "fl ounce", "fl ounces", "fluid oz"])
        add("cup", ["c", "cups", "cupful"])
        add("pint", ["pt", "pts"])
        add("quart", ["qt", "qts"])
        add("gallon", ["gal", "gals"])
        add("milliliter", ["ml", "mls", "milliliter", "milliliters", "millilitre", "millilitres", "cc"])
        add("liter", ["l", "ltr", "liter", "liters", "litre", "litres"])
        add("ounce", ["oz", "ozs", "ounce", "ounces"])
        add("pound", ["lb", "lbs", "pound", "pounds", "#"])
        add("gram", ["g", "gm", "gms", "gr", "grams", "gram", "gramme", "grammes"])
        add("kilogram", ["kg", "kgs", "kilo", "kilos"])
        add("package", ["pkg", "pkgs", "packet", "packets", "pack", "packs"])
        add("can", ["tin", "tins"])
        add("bunch", ["bunches"])
        add("clove", ["cloves"])
        add("piece", ["pc", "pcs"])
        add("stick", ["sticks"])
        add("envelope", ["env", "sachet", "sachets"])
        return map
    }()

    static func info(_ id: String?) -> UnitInfo? {
        guard let id else { return nil }
        return byID[id]
    }

    /// The canonical unit for a token as written, or nil if it is not one.
    /// Case matters for the one ambiguous pair: "T" is a tablespoon and "t"
    /// a teaspoon.
    static func canonical(_ token: String) -> UnitInfo? {
        var cleaned = token.trimmingCharacters(in: .whitespaces)
        while cleaned.hasSuffix(".") { cleaned.removeLast() }
        guard !cleaned.isEmpty else { return nil }
        if cleaned == "T" { return byID["tablespoon"] }
        if cleaned == "t" { return byID["teaspoon"] }
        if let id = aliases[cleaned.lowercased()] { return byID[id] }
        return nil
    }

    static func isUnitWord(_ token: String) -> Bool {
        canonical(token) != nil
    }

    // MARK: Conversion

    /// Converts into the other measurement system, picking the unit a cook
    /// would actually reach for at that size.
    static func convert(_ quantity: Double, unit: UnitInfo, to system: UnitSystem) -> (Double, UnitInfo) {
        guard unit.kind != .count, let from = unit.system, from != system else { return (quantity, unit) }
        let base = quantity * unit.toBase
        switch (unit.kind, system) {
        case (.volume, .metric):
            if base >= 1000 { return (base / 1000, byID["liter"]!) }
            return (roundVolume(base), byID["milliliter"]!)
        case (.weight, .metric):
            if base >= 1000 { return (base / 1000, byID["kilogram"]!) }
            return (roundedGrams(base), byID["gram"]!)
        case (.volume, .us):
            let tsp = base / 4.929
            if tsp < 3 { return (tsp, byID["teaspoon"]!) }
            let tbsp = base / 14.787
            if tbsp < 4 { return (tbsp, byID["tablespoon"]!) }
            let cups = base / 236.588
            if cups < 4 { return (cups, byID["cup"]!) }
            let quarts = base / 946.353
            if quarts < 4 { return (quarts, byID["quart"]!) }
            return (base / 3785.41, byID["gallon"]!)
        case (.weight, .us):
            let ounces = base / 28.3495
            if ounces < 16 { return (ounces, byID["ounce"]!) }
            return (base / 453.592, byID["pound"]!)
        case (.count, _):
            return (quantity, unit)
        }
    }

    private static func roundVolume(_ ml: Double) -> Double {
        if ml < 10 { return (ml * 2).rounded() / 2 }
        if ml < 100 { return (ml / 5).rounded() * 5 }
        return (ml / 10).rounded() * 10
    }

    private static func roundedGrams(_ g: Double) -> Double {
        if g < 10 { return g.rounded() }
        if g < 100 { return (g / 5).rounded() * 5 }
        return (g / 10).rounded() * 10
    }

    /// Whether two stored unit ids can be summed after conversion.
    static func compatible(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        if a == b { return true }
        guard let ia = info(a), let ib = info(b), ia.kind != .count, ib.kind != .count else { return false }
        return ia.kind == ib.kind
    }

    /// Adds `quantity` of `unit` into `total` of `totalUnit`, returning the sum
    /// in whichever of the two units is larger.
    static func sum(_ total: Double, _ totalUnit: String?, plus quantity: Double, _ unit: String?) -> (Double, String?)? {
        guard compatible(totalUnit, unit) else { return nil }
        if totalUnit == unit { return (total + quantity, unit) }
        guard let a = info(totalUnit), let b = info(unit) else { return nil }
        let larger = a.toBase >= b.toBase ? a : b
        let base = total * a.toBase + quantity * b.toBase
        return (base / larger.toBase, larger.id)
    }
}

// MARK: - Display

enum QuantityText {
    /// "1½ cups", "2 tbsp", "3", "a pinch" for the given scale and system.
    static func string(quantity: Double?, quantityMax: Double?, unit: String?, scale: Double, system: UnitSystem, abbreviated: Bool = false) -> String {
        guard let quantity else {
            if let unit, let info = Units.info(unit) {
                return info.kind == .count ? info.singular : ""
            }
            return unit ?? ""
        }
        var low = quantity * scale
        var high = quantityMax.map { $0 * scale }
        var unitInfo = Units.info(unit)
        var unitText = unit ?? ""

        if let info = unitInfo, info.kind != .count, let from = info.system, from != system {
            let (converted, target) = Units.convert(low, unit: info, to: system)
            low = converted
            if let h = high {
                high = Units.convert(h, unit: info, to: system).0
            }
            unitInfo = target
        }

        if let info = unitInfo {
            let metric = info.system == .metric
            unitText = info.name(for: high ?? low, abbreviated: abbreviated || metric)
        }

        let number: String
        if unitInfo?.system == .metric {
            number = metricNumber(low) + (high.map { "–" + metricNumber($0) } ?? "")
        } else {
            number = Fractions.string(low) + (high.map { "–" + Fractions.string($0) } ?? "")
        }
        return unitText.isEmpty ? number : "\(number) \(unitText)"
    }

    private static func metricNumber(_ value: Double) -> String {
        if value >= 10 { return String(Int(value.rounded())) }
        let one = (value * 10).rounded() / 10
        if one == one.rounded() { return String(Int(one)) }
        return String(format: "%.1f", one)
    }

    /// Fahrenheit in a step, shown in Celsius too when the reader is metric.
    static func localizeTemperatures(in text: String, system: UnitSystem) -> String {
        guard system == .metric else { return text }
        guard let regex = try? NSRegularExpression(pattern: #"(\d{2,3})\s*(?:°|º|degrees?)\s*(?:F\b|Fahrenheit\b)"#, options: [.caseInsensitive]) else { return text }
        let ns = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            guard let f = Int(ns.substring(with: match.range(at: 1))) else { continue }
            let c = Int(((Double(f) - 32) * 5 / 9 / 5).rounded() * 5)
            let original = ns.substring(with: match.range)
            result = (result as NSString).replacingCharacters(in: match.range, with: "\(original) (\(c)°C)")
        }
        return result
    }
}
