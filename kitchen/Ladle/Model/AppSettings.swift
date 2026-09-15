import Foundation

struct AppSettings: Codable, Hashable {
    var unitSystem: UnitSystem = .us
    /// Treat salt, pepper, oil and the like as always on hand.
    var assumeStaples: Bool = true
    /// Canonical ingredient keys assumed present.
    var staples: [String] = IngredientCatalog.defaultStaples
    /// Speak each step as it appears in cook mode.
    var readAloud: Bool = false
    /// Start listening for voice commands as soon as cook mode opens.
    var voiceOnByDefault: Bool = false
    var keepScreenAwake: Bool = true
    var largeCookText: Bool = false
    var haptics: Bool = true
    var hasOnboarded: Bool = false
    var lastInboxCheck: Date?

    init() {}

    enum CodingKeys: String, CodingKey {
        case unitSystem, assumeStaples, staples, readAloud, voiceOnByDefault, keepScreenAwake,
             largeCookText, haptics, hasOnboarded, lastInboxCheck
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unitSystem = try c.decodeIfPresent(UnitSystem.self, forKey: .unitSystem) ?? .us
        assumeStaples = try c.decodeIfPresent(Bool.self, forKey: .assumeStaples) ?? true
        staples = try c.decodeIfPresent([String].self, forKey: .staples) ?? IngredientCatalog.defaultStaples
        readAloud = try c.decodeIfPresent(Bool.self, forKey: .readAloud) ?? false
        voiceOnByDefault = try c.decodeIfPresent(Bool.self, forKey: .voiceOnByDefault) ?? false
        keepScreenAwake = try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? true
        largeCookText = try c.decodeIfPresent(Bool.self, forKey: .largeCookText) ?? false
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        hasOnboarded = try c.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? false
        lastInboxCheck = try c.decodeIfPresent(Date.self, forKey: .lastInboxCheck)
    }
}
