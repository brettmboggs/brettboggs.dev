import Foundation

/// Ready-made groups of what most kitchens of a kind already have. Picking
/// one puts its items on the review list, checked, so the few that are not
/// there get unchecked instead of everything else getting typed.
///
/// Every name here must be a catalog name exactly; `check_swift.py` fails
/// if one is not.
struct PantryKit: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let items: [String]
}

enum PantryKits {
    static let all: [PantryKit] = [
        PantryKit(id: "baking", title: "Baking basics", systemImage: "birthday.cake", items: [
            "all-purpose flour", "granulated sugar", "brown sugar", "powdered sugar", "baking soda",
            "baking powder", "vanilla extract", "cornstarch", "cocoa powder", "chocolate chips",
            "salt", "butter", "eggs", "milk", "vegetable oil", "honey",
        ]),
        PantryKit(id: "spices", title: "Spice rack", systemImage: "leaf", items: [
            "salt", "black pepper", "garlic powder", "onion powder", "paprika", "smoked paprika",
            "cumin", "chili powder", "cayenne pepper", "red pepper flakes", "dried oregano",
            "italian seasoning", "thyme", "bay leaves", "cinnamon", "nutmeg", "ginger powder",
        ]),
        PantryKit(id: "fridge", title: "Fridge staples", systemImage: "refrigerator", items: [
            "butter", "eggs", "milk", "cheddar cheese", "parmesan", "sour cream", "cream cheese",
            "yogurt", "mayonnaise", "ketchup", "mustard", "dijon mustard", "hot sauce", "bacon",
        ]),
        PantryKit(id: "shelf", title: "Pantry shelf", systemImage: "cabinet", items: [
            "rice", "pasta", "chicken broth", "canned tomatoes", "tomato paste", "tomato sauce",
            "black beans", "chickpeas", "rolled oats", "peanut butter", "bread crumbs", "olive oil",
            "vegetable oil", "white vinegar", "apple cider vinegar", "soy sauce",
        ]),
        PantryKit(id: "produce", title: "Produce basics", systemImage: "carrot", items: [
            "onion", "garlic", "potatoes", "carrots", "celery", "lemon", "lime", "tomatoes",
            "green onions", "bell pepper", "apples", "bananas",
        ]),
        PantryKit(id: "mexican", title: "Taco night", systemImage: "flame", items: [
            "tortillas", "tortilla chips", "black beans", "pinto beans", "salsa", "taco seasoning",
            "cumin", "chili powder", "jalapeño", "cilantro", "lime", "avocado", "monterey jack",
            "sour cream", "rice",
        ]),
        PantryKit(id: "italian", title: "Italian", systemImage: "fork.knife", items: [
            "pasta", "olive oil", "garlic", "canned tomatoes", "tomato paste", "parmesan",
            "mozzarella", "ricotta", "basil", "italian seasoning", "red pepper flakes",
            "balsamic vinegar", "onion",
        ]),
        PantryKit(id: "asian", title: "Asian pantry", systemImage: "takeoutbag.and.cup.and.straw", items: [
            "soy sauce", "rice vinegar", "sesame oil", "fish sauce", "hoisin sauce", "oyster sauce",
            "sriracha", "ginger", "garlic", "green onions", "rice", "cornstarch", "coconut milk",
            "sesame seeds",
        ]),
        PantryKit(id: "freezer", title: "Freezer", systemImage: "snowflake", items: [
            "frozen vegetables", "peas", "corn", "frozen fruit", "hash browns", "ground beef",
            "chicken breast", "ice cream",
        ]),
    ]
}
