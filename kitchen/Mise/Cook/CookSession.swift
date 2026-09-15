import Foundation
import Observation

/// The recipe being cooked right now, if any. Shared so Siri and the voice
/// listener can move it along without going through a view.
@MainActor
@Observable
final class CookSession {
    static let shared = CookSession()

    private(set) var recipe: Recipe?
    private(set) var stepIndex: Int = 0
    var scale: Double = 1
    var startedAt: Date?

    var isActive: Bool { recipe != nil }

    /// Steps without headings; headings are shown as context, not visited.
    var steps: [Step] { recipe?.realSteps ?? [] }

    var currentStep: Step? {
        guard stepIndex >= 0, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    var isFirst: Bool { stepIndex <= 0 }
    var isLast: Bool { stepIndex >= steps.count - 1 }
    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(stepIndex + 1) / Double(steps.count)
    }

    /// The heading a step sits under, if the method has sections.
    var currentHeading: String? {
        guard let recipe, let current = currentStep else { return nil }
        var heading: String?
        for step in recipe.steps {
            if step.isHeading { heading = step.text }
            if step.id == current.id { return heading }
        }
        return nil
    }

    func start(_ recipe: Recipe, scale: Double = 1, at index: Int = 0) {
        self.recipe = recipe
        self.scale = scale
        self.stepIndex = min(max(0, index), max(0, recipe.realSteps.count - 1))
        self.startedAt = Date()
    }

    /// Keeps the session pointed at the latest copy after an edit.
    func refresh(from library: Library) {
        guard let current = recipe, let latest = library.recipe(current.id) else { return }
        recipe = latest
        stepIndex = min(stepIndex, max(0, latest.realSteps.count - 1))
    }

    @discardableResult
    func next() -> Bool {
        guard !isLast else { return false }
        stepIndex += 1
        return true
    }

    @discardableResult
    func back() -> Bool {
        guard !isFirst else { return false }
        stepIndex -= 1
        return true
    }

    func jump(to index: Int) {
        stepIndex = min(max(0, index), max(0, steps.count - 1))
    }

    func end() {
        recipe = nil
        stepIndex = 0
        scale = 1
        startedAt = nil
    }

    /// Timers written into the current step.
    var detectedTimers: [DetectedTimer] {
        guard let step = currentStep else { return [] }
        return TimerDetector.detect(in: step.text)
    }

    /// Ingredients the current step talks about, with their scaled amounts.
    var ingredientsForStep: [Ingredient] {
        guard let recipe, let step = currentStep else { return [] }
        return recipe.ingredientsMentioned(in: step)
    }

    /// What to say when asked "how much flour".
    func answer(howMuch query: String, system: UnitSystem) -> String? {
        guard let recipe else { return nil }
        let words = IngredientKey.significantWords(query)
        guard !words.isEmpty else { return nil }
        let matches = recipe.realIngredients.filter { ingredient in
            let own = IngredientKey.significantWords(ingredient.name)
            return words.contains { word in own.contains(word) || ingredient.key.contains(word) }
        }
        guard !matches.isEmpty else { return nil }
        return matches.map { IngredientLine.text($0, scale: scale, system: system) }.joined(separator: ". ")
    }

    /// The current step, spoken.
    func spokenStep(system: UnitSystem) -> String? {
        guard let step = currentStep else { return nil }
        let number = stepIndex + 1
        var text = "Step \(number). " + QuantityText.localizeTemperatures(in: step.text, system: system)
        if isLast { text += " That is the last step." }
        return text
    }
}
