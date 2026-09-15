import Foundation

enum Aisle: String, Codable, CaseIterable, Identifiable {
    case produce
    case meat
    case seafood
    case dairy
    case bakery
    case baking
    case spices
    case pantry
    case condiments
    case frozen
    case beverages
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .produce: return "Produce"
        case .meat: return "Meat"
        case .seafood: return "Seafood"
        case .dairy: return "Dairy & Eggs"
        case .bakery: return "Bakery"
        case .baking: return "Baking"
        case .spices: return "Spices"
        case .pantry: return "Pantry"
        case .condiments: return "Condiments & Oils"
        case .frozen: return "Frozen"
        case .beverages: return "Drinks"
        case .other: return "Other"
        }
    }

    var order: Int { Aisle.allCases.firstIndex(of: self) ?? 99 }
}

struct CatalogEntry {
    let name: String
    let aliases: [String]
    let aisle: Aisle
    /// A more general ingredient this one can stand in for: cheddar → cheese.
    let parent: String?
    let staple: Bool

    init(_ name: String, _ aliases: [String] = [], _ aisle: Aisle, parent: String? = nil, staple: Bool = false) {
        self.name = name
        self.aliases = aliases
        self.aisle = aisle
        self.parent = parent
        self.staple = staple
    }
}

/// What the kitchen knows about ingredients: the name a thing goes by, the
/// other names it goes by, where it is in the shop, and what it can stand in
/// for. Matching never depends on this being complete; an unknown ingredient
/// simply matches on its own words.
enum IngredientCatalog {
    static let entries: [CatalogEntry] = [
        // Baking
        CatalogEntry("all-purpose flour", ["flour", "plain flour", "ap flour", "white flour", "unbleached flour"], .baking, staple: true),
        CatalogEntry("bread flour", ["strong flour"], .baking, parent: "all-purpose flour"),
        CatalogEntry("cake flour", ["pastry flour"], .baking, parent: "all-purpose flour"),
        CatalogEntry("whole wheat flour", ["wholemeal flour", "whole-wheat flour"], .baking, parent: "all-purpose flour"),
        CatalogEntry("self-rising flour", ["self raising flour", "self-raising flour"], .baking),
        CatalogEntry("almond flour", ["almond meal", "ground almonds"], .baking),
        CatalogEntry("cornmeal", ["polenta", "corn meal"], .baking),
        CatalogEntry("cornstarch", ["corn starch", "cornflour", "corn flour"], .baking, staple: true),
        CatalogEntry("granulated sugar", ["sugar", "white sugar", "caster sugar", "superfine sugar", "cane sugar"], .baking, staple: true),
        CatalogEntry("brown sugar", ["light brown sugar", "dark brown sugar", "packed brown sugar", "demerara sugar", "muscovado sugar"], .baking, staple: true),
        CatalogEntry("powdered sugar", ["confectioners sugar", "confectioner's sugar", "icing sugar", "confectioners' sugar", "10x sugar"], .baking),
        CatalogEntry("baking soda", ["bicarbonate of soda", "bicarb", "sodium bicarbonate"], .baking, staple: true),
        CatalogEntry("baking powder", [], .baking, staple: true),
        CatalogEntry("active dry yeast", ["yeast", "dry yeast", "instant yeast", "rapid rise yeast", "bread machine yeast"], .baking),
        CatalogEntry("vanilla extract", ["vanilla", "pure vanilla extract", "vanilla essence"], .baking, staple: true),
        CatalogEntry("almond extract", [], .baking),
        CatalogEntry("cocoa powder", ["cocoa", "unsweetened cocoa powder", "dutch process cocoa", "cacao powder"], .baking),
        CatalogEntry("chocolate chips", ["semisweet chocolate chips", "semi-sweet chocolate chips", "chocolate morsels", "milk chocolate chips"], .baking, parent: "chocolate"),
        CatalogEntry("chocolate", ["dark chocolate", "bittersweet chocolate", "semisweet chocolate", "baking chocolate", "unsweetened chocolate", "milk chocolate"], .baking),
        CatalogEntry("white chocolate", ["white chocolate chips"], .baking),
        CatalogEntry("honey", [], .baking, staple: true),
        CatalogEntry("maple syrup", ["pure maple syrup"], .baking),
        CatalogEntry("molasses", ["treacle", "black treacle"], .baking),
        CatalogEntry("corn syrup", ["light corn syrup", "golden syrup", "dark corn syrup"], .baking),
        CatalogEntry("sweetened condensed milk", ["condensed milk"], .baking),
        CatalogEntry("evaporated milk", [], .baking),
        CatalogEntry("shortening", ["vegetable shortening", "crisco", "lard"], .baking),
        CatalogEntry("rolled oats", ["oats", "old-fashioned oats", "old fashioned oats", "quick oats", "oatmeal", "porridge oats"], .baking),
        CatalogEntry("graham crackers", ["graham cracker crumbs", "digestive biscuits"], .baking),
        CatalogEntry("gelatin", ["unflavored gelatin", "gelatine"], .baking),
        CatalogEntry("food coloring", ["food colouring", "food dye"], .baking),
        CatalogEntry("sprinkles", ["jimmies"], .baking),
        CatalogEntry("coconut flakes", ["shredded coconut", "sweetened coconut", "desiccated coconut", "coconut"], .baking),
        CatalogEntry("pecans", ["pecan halves", "chopped pecans"], .baking),
        CatalogEntry("walnuts", ["chopped walnuts", "walnut halves"], .baking),
        CatalogEntry("almonds", ["sliced almonds", "slivered almonds", "blanched almonds"], .baking),
        CatalogEntry("peanuts", ["roasted peanuts", "dry roasted peanuts"], .baking),
        CatalogEntry("cashews", [], .baking),
        CatalogEntry("pine nuts", ["pignoli"], .baking),
        CatalogEntry("raisins", ["golden raisins", "sultanas"], .baking),
        CatalogEntry("dried cranberries", ["craisins"], .baking),
        CatalogEntry("dates", ["medjool dates", "pitted dates"], .baking),
        CatalogEntry("sesame seeds", ["toasted sesame seeds"], .baking),
        CatalogEntry("poppy seeds", [], .baking),
        CatalogEntry("chia seeds", [], .baking),
        CatalogEntry("flaxseed", ["ground flaxseed", "flax seed", "flax meal"], .baking),
        CatalogEntry("peanut butter", ["creamy peanut butter", "crunchy peanut butter"], .pantry),
        CatalogEntry("almond butter", [], .pantry),
        CatalogEntry("nutella", ["chocolate hazelnut spread"], .pantry),

        // Dairy & eggs
        CatalogEntry("eggs", ["egg", "large eggs", "large egg", "whole eggs"], .dairy),
        CatalogEntry("egg whites", ["egg white"], .dairy, parent: "eggs"),
        CatalogEntry("egg yolks", ["egg yolk"], .dairy, parent: "eggs"),
        CatalogEntry("butter", ["unsalted butter", "salted butter", "sweet butter", "stick butter"], .dairy, staple: true),
        CatalogEntry("milk", ["whole milk", "2% milk", "skim milk", "low-fat milk", "1% milk", "reduced-fat milk"], .dairy),
        CatalogEntry("buttermilk", [], .dairy),
        CatalogEntry("heavy cream", ["heavy whipping cream", "whipping cream", "double cream", "cream"], .dairy),
        CatalogEntry("half and half", ["half-and-half", "single cream", "light cream"], .dairy, parent: "heavy cream"),
        CatalogEntry("sour cream", ["soured cream"], .dairy),
        CatalogEntry("cream cheese", ["neufchatel"], .dairy),
        CatalogEntry("yogurt", ["plain yogurt", "greek yogurt", "plain greek yogurt", "yoghurt", "natural yogurt"], .dairy),
        CatalogEntry("cheese", ["shredded cheese", "grated cheese"], .dairy),
        CatalogEntry("cheddar cheese", ["cheddar", "sharp cheddar", "shredded cheddar", "sharp cheddar cheese", "mild cheddar"], .dairy, parent: "cheese"),
        CatalogEntry("mozzarella", ["mozzarella cheese", "fresh mozzarella", "shredded mozzarella"], .dairy, parent: "cheese"),
        CatalogEntry("parmesan", ["parmesan cheese", "parmigiano reggiano", "parmigiano-reggiano", "grated parmesan", "pecorino", "pecorino romano"], .dairy, parent: "cheese"),
        CatalogEntry("feta", ["feta cheese", "crumbled feta"], .dairy, parent: "cheese"),
        CatalogEntry("goat cheese", ["chevre"], .dairy, parent: "cheese"),
        CatalogEntry("ricotta", ["ricotta cheese", "whole milk ricotta"], .dairy, parent: "cheese"),
        CatalogEntry("cottage cheese", [], .dairy, parent: "cheese"),
        CatalogEntry("swiss cheese", ["gruyere", "gruyère", "emmental", "swiss"], .dairy, parent: "cheese"),
        CatalogEntry("monterey jack", ["jack cheese", "pepper jack", "pepper jack cheese", "colby jack", "colby"], .dairy, parent: "cheese"),
        CatalogEntry("blue cheese", ["gorgonzola", "roquefort", "stilton"], .dairy, parent: "cheese"),
        CatalogEntry("brie", ["camembert"], .dairy, parent: "cheese"),
        CatalogEntry("velveeta", ["american cheese", "processed cheese"], .dairy, parent: "cheese"),
        CatalogEntry("mascarpone", [], .dairy, parent: "cream cheese"),
        CatalogEntry("whipped topping", ["cool whip", "whipped cream"], .dairy),
        CatalogEntry("ice cream", ["vanilla ice cream"], .frozen),

        // Meat
        CatalogEntry("chicken", ["whole chicken", "chicken pieces"], .meat),
        CatalogEntry("chicken breast", ["chicken breasts", "boneless skinless chicken breast", "chicken breast halves", "chicken cutlets"], .meat, parent: "chicken"),
        CatalogEntry("chicken thighs", ["chicken thigh", "boneless skinless chicken thighs", "bone-in chicken thighs"], .meat, parent: "chicken"),
        CatalogEntry("chicken wings", ["wings", "chicken wing"], .meat, parent: "chicken"),
        CatalogEntry("chicken drumsticks", ["drumsticks", "chicken legs"], .meat, parent: "chicken"),
        CatalogEntry("ground chicken", [], .meat, parent: "chicken"),
        CatalogEntry("rotisserie chicken", ["cooked chicken", "shredded chicken", "leftover chicken", "cooked shredded chicken"], .meat, parent: "chicken"),
        CatalogEntry("turkey", ["whole turkey", "turkey breast"], .meat),
        CatalogEntry("ground turkey", [], .meat, parent: "turkey"),
        CatalogEntry("deli turkey", ["sliced turkey", "turkey slices"], .meat, parent: "turkey"),
        CatalogEntry("ground beef", ["hamburger", "hamburger meat", "minced beef", "lean ground beef", "ground chuck", "beef mince", "ground sirloin"], .meat, parent: "beef"),
        CatalogEntry("beef", ["beef roast", "chuck roast", "beef chuck", "pot roast", "beef stew meat", "stew meat", "stewing beef", "beef brisket", "brisket", "beef short ribs", "short ribs", "flank steak", "skirt steak", "sirloin", "ribeye", "rib eye", "new york strip", "filet mignon", "beef tenderloin", "round steak", "steak", "steaks"], .meat),
        CatalogEntry("corned beef", [], .meat, parent: "beef"),
        CatalogEntry("pork", ["pork shoulder", "pork butt", "boston butt", "pork loin", "pork tenderloin", "pork roast"], .meat),
        CatalogEntry("pork chops", ["pork chop", "bone-in pork chops", "boneless pork chops"], .meat, parent: "pork"),
        CatalogEntry("ground pork", ["pork mince", "minced pork"], .meat, parent: "pork"),
        CatalogEntry("bacon", ["thick-cut bacon", "bacon slices", "streaky bacon", "bacon strips"], .meat),
        CatalogEntry("pancetta", [], .meat, parent: "bacon"),
        CatalogEntry("ham", ["cooked ham", "diced ham", "ham steak", "deli ham", "sliced ham", "ham hock"], .meat),
        CatalogEntry("prosciutto", [], .meat, parent: "ham"),
        CatalogEntry("sausage", ["pork sausage", "breakfast sausage", "sausage links", "sausage meat", "bulk sausage", "ground sausage"], .meat),
        CatalogEntry("italian sausage", ["sweet italian sausage", "hot italian sausage", "italian sausages"], .meat, parent: "sausage"),
        CatalogEntry("chorizo", [], .meat, parent: "sausage"),
        CatalogEntry("kielbasa", ["smoked sausage", "polish sausage", "andouille", "andouille sausage"], .meat, parent: "sausage"),
        CatalogEntry("hot dogs", ["hot dog", "frankfurters", "franks", "wieners"], .meat),
        CatalogEntry("pepperoni", ["sliced pepperoni"], .meat),
        CatalogEntry("salami", [], .meat),
        CatalogEntry("lamb", ["lamb chops", "leg of lamb", "lamb shoulder", "ground lamb", "lamb shanks"], .meat),
        CatalogEntry("veal", [], .meat),
        CatalogEntry("ribs", ["baby back ribs", "pork ribs", "spare ribs", "spareribs"], .meat, parent: "pork"),

        // Seafood
        CatalogEntry("shrimp", ["prawns", "prawn", "jumbo shrimp", "large shrimp", "raw shrimp"], .seafood),
        CatalogEntry("salmon", ["salmon fillets", "salmon fillet", "smoked salmon"], .seafood),
        CatalogEntry("tuna", ["canned tuna", "tuna steak", "tuna steaks", "albacore tuna"], .seafood),
        CatalogEntry("white fish", ["cod", "tilapia", "halibut", "haddock", "sole", "flounder", "mahi mahi", "sea bass", "snapper", "fish fillets", "fish fillet", "fish", "catfish", "pollock", "grouper"], .seafood),
        CatalogEntry("crab", ["crab meat", "crabmeat", "lump crab meat", "imitation crab"], .seafood),
        CatalogEntry("scallops", ["sea scallops", "bay scallops"], .seafood),
        CatalogEntry("clams", ["canned clams", "chopped clams", "littleneck clams"], .seafood),
        CatalogEntry("mussels", [], .seafood),
        CatalogEntry("lobster", ["lobster tails", "lobster meat"], .seafood),
        CatalogEntry("anchovies", ["anchovy", "anchovy fillets", "anchovy paste"], .seafood),
        CatalogEntry("sardines", [], .seafood),

        // Produce
        CatalogEntry("onion", ["onions", "yellow onion", "yellow onions", "white onion", "sweet onion", "vidalia onion", "spanish onion", "brown onion"], .produce, staple: true),
        CatalogEntry("red onion", ["red onions", "purple onion"], .produce, parent: "onion"),
        CatalogEntry("green onions", ["scallions", "scallion", "green onion", "spring onions", "spring onion"], .produce),
        CatalogEntry("shallot", ["shallots"], .produce, parent: "onion"),
        CatalogEntry("leek", ["leeks"], .produce),
        CatalogEntry("garlic", ["garlic cloves", "garlic clove", "cloves garlic", "clove garlic", "fresh garlic", "minced garlic", "garlic bulb", "head of garlic"], .produce, staple: true),
        CatalogEntry("ginger", ["fresh ginger", "ginger root", "gingerroot", "grated ginger"], .produce),
        CatalogEntry("potatoes", ["potato", "russet potatoes", "russet potato", "yukon gold potatoes", "yukon gold", "red potatoes", "baking potatoes", "new potatoes", "baby potatoes", "fingerling potatoes", "idaho potatoes"], .produce),
        CatalogEntry("sweet potatoes", ["sweet potato", "yams", "yam"], .produce),
        CatalogEntry("carrots", ["carrot", "baby carrots", "shredded carrots"], .produce),
        CatalogEntry("celery", ["celery stalks", "celery stalk", "celery ribs", "celery rib"], .produce),
        CatalogEntry("bell pepper", ["bell peppers", "red bell pepper", "green bell pepper", "yellow bell pepper", "orange bell pepper", "red pepper", "green pepper", "sweet pepper", "capsicum"], .produce),
        CatalogEntry("jalapeño", ["jalapeno", "jalapenos", "jalapeños", "jalapeno pepper", "jalapeño pepper", "jalapeno peppers"], .produce),
        CatalogEntry("serrano pepper", ["serrano", "serrano chile", "serrano chili"], .produce, parent: "jalapeño"),
        CatalogEntry("poblano pepper", ["poblano", "poblanos", "poblano peppers"], .produce, parent: "bell pepper"),
        CatalogEntry("chile peppers", ["chili pepper", "chile pepper", "chiles", "chilies", "chillies", "hot peppers", "thai chiles", "bird's eye chiles", "fresno chile", "habanero", "habaneros", "red chili", "green chili", "green chiles", "canned green chiles", "diced green chiles"], .produce),
        CatalogEntry("chipotle peppers in adobo", ["chipotles in adobo", "chipotle in adobo", "chipotle chiles in adobo sauce", "chipotle peppers", "chipotle pepper in adobo"], .pantry),
        CatalogEntry("tomatoes", ["tomato", "roma tomatoes", "roma tomato", "plum tomatoes", "beefsteak tomatoes", "vine tomatoes", "ripe tomatoes", "fresh tomatoes"], .produce),
        CatalogEntry("cherry tomatoes", ["grape tomatoes", "cherry tomato", "grape tomato"], .produce, parent: "tomatoes"),
        CatalogEntry("canned tomatoes", ["diced tomatoes", "crushed tomatoes", "whole peeled tomatoes", "canned diced tomatoes", "stewed tomatoes", "fire roasted tomatoes", "fire-roasted tomatoes", "san marzano tomatoes", "petite diced tomatoes", "chopped tomatoes"], .pantry),
        CatalogEntry("tomato paste", ["tomato puree", "tomato purée"], .pantry),
        CatalogEntry("tomato sauce", ["passata", "marinara", "marinara sauce", "pasta sauce", "spaghetti sauce", "pizza sauce"], .pantry),
        CatalogEntry("sun-dried tomatoes", ["sundried tomatoes", "sun dried tomatoes"], .pantry),
        CatalogEntry("cucumber", ["cucumbers", "english cucumber", "persian cucumbers"], .produce),
        CatalogEntry("zucchini", ["courgette", "courgettes", "zucchinis", "summer squash", "yellow squash"], .produce),
        CatalogEntry("butternut squash", ["winter squash", "acorn squash", "kabocha squash", "delicata squash"], .produce),
        CatalogEntry("pumpkin", ["pumpkin puree", "canned pumpkin", "pumpkin purée", "pure pumpkin"], .pantry),
        CatalogEntry("eggplant", ["aubergine", "eggplants"], .produce),
        CatalogEntry("mushrooms", ["mushroom", "button mushrooms", "cremini mushrooms", "baby bella mushrooms", "white mushrooms", "portobello mushrooms", "shiitake mushrooms", "sliced mushrooms", "crimini mushrooms", "baby portobello mushrooms"], .produce),
        CatalogEntry("broccoli", ["broccoli florets", "broccolini"], .produce),
        CatalogEntry("cauliflower", ["cauliflower florets", "cauliflower rice", "riced cauliflower"], .produce),
        CatalogEntry("cabbage", ["green cabbage", "red cabbage", "napa cabbage", "savoy cabbage", "coleslaw mix", "shredded cabbage"], .produce),
        CatalogEntry("brussels sprouts", ["brussel sprouts", "brussels sprout"], .produce),
        CatalogEntry("kale", ["lacinato kale", "tuscan kale", "curly kale", "baby kale"], .produce),
        CatalogEntry("spinach", ["baby spinach", "fresh spinach", "spinach leaves"], .produce),
        CatalogEntry("frozen spinach", ["chopped frozen spinach", "frozen chopped spinach"], .frozen, parent: "spinach"),
        CatalogEntry("lettuce", ["romaine", "romaine lettuce", "iceberg lettuce", "butter lettuce", "mixed greens", "salad greens", "spring mix", "arugula", "rocket", "green leaf lettuce", "bibb lettuce", "salad mix"], .produce),
        CatalogEntry("asparagus", ["asparagus spears"], .produce),
        CatalogEntry("green beans", ["string beans", "french beans", "haricots verts", "fresh green beans"], .produce),
        CatalogEntry("peas", ["frozen peas", "green peas", "sweet peas", "petite peas"], .frozen),
        CatalogEntry("corn", ["corn kernels", "frozen corn", "sweet corn", "canned corn", "corn on the cob", "ears of corn", "ears corn"], .produce),
        CatalogEntry("avocado", ["avocados", "ripe avocado", "hass avocado"], .produce),
        CatalogEntry("lemon", ["lemons", "fresh lemon"], .produce),
        CatalogEntry("lemon juice", ["fresh lemon juice", "juice of 1 lemon", "juice of one lemon", "freshly squeezed lemon juice"], .produce, parent: "lemon"),
        CatalogEntry("lemon zest", ["zest of 1 lemon", "grated lemon zest", "grated lemon peel", "lemon peel"], .produce, parent: "lemon"),
        CatalogEntry("lime", ["limes", "fresh lime"], .produce),
        CatalogEntry("lime juice", ["fresh lime juice", "juice of 1 lime", "juice of one lime"], .produce, parent: "lime"),
        CatalogEntry("lime zest", ["zest of 1 lime"], .produce, parent: "lime"),
        CatalogEntry("orange", ["oranges", "navel orange", "orange juice", "fresh orange juice", "orange zest", "zest of 1 orange", "clementines", "mandarin oranges"], .produce),
        CatalogEntry("apples", ["apple", "granny smith apples", "granny smith apple", "honeycrisp apples", "gala apples", "tart apples", "baking apples"], .produce),
        CatalogEntry("bananas", ["banana", "ripe bananas", "ripe banana", "overripe bananas"], .produce),
        CatalogEntry("berries", ["mixed berries", "fresh berries", "frozen berries", "frozen mixed berries"], .produce),
        CatalogEntry("strawberries", ["strawberry", "fresh strawberries", "frozen strawberries"], .produce, parent: "berries"),
        CatalogEntry("blueberries", ["blueberry", "fresh blueberries", "frozen blueberries"], .produce, parent: "berries"),
        CatalogEntry("raspberries", ["raspberry"], .produce, parent: "berries"),
        CatalogEntry("blackberries", ["blackberry"], .produce, parent: "berries"),
        CatalogEntry("cranberries", ["fresh cranberries", "frozen cranberries", "cranberry"], .produce),
        CatalogEntry("peaches", ["peach", "nectarines", "nectarine", "fresh peaches"], .produce),
        CatalogEntry("pears", ["pear"], .produce),
        CatalogEntry("cherries", ["cherry", "fresh cherries", "frozen cherries", "pitted cherries"], .produce),
        CatalogEntry("grapes", ["grape", "red grapes", "green grapes", "seedless grapes"], .produce),
        CatalogEntry("pineapple", ["fresh pineapple", "pineapple chunks", "crushed pineapple", "canned pineapple"], .produce),
        CatalogEntry("mango", ["mangoes", "mangos", "fresh mango"], .produce),
        CatalogEntry("watermelon", [], .produce),
        CatalogEntry("plums", ["plum"], .produce),
        CatalogEntry("figs", ["fig", "fresh figs", "dried figs"], .produce),
        CatalogEntry("rhubarb", [], .produce),
        CatalogEntry("coconut milk", ["canned coconut milk", "full-fat coconut milk", "light coconut milk", "coconut cream"], .pantry),
        CatalogEntry("cilantro", ["fresh cilantro", "coriander leaves", "fresh coriander", "cilantro leaves", "chopped cilantro"], .produce),
        CatalogEntry("parsley", ["fresh parsley", "flat-leaf parsley", "flat leaf parsley", "italian parsley", "curly parsley", "chopped parsley"], .produce),
        CatalogEntry("basil", ["fresh basil", "basil leaves", "fresh basil leaves", "thai basil"], .produce),
        CatalogEntry("mint", ["fresh mint", "mint leaves"], .produce),
        CatalogEntry("dill", ["fresh dill", "dill weed"], .produce),
        CatalogEntry("rosemary", ["fresh rosemary", "rosemary sprigs", "dried rosemary"], .produce),
        CatalogEntry("thyme", ["fresh thyme", "thyme sprigs", "thyme leaves", "dried thyme"], .produce),
        CatalogEntry("sage", ["fresh sage", "sage leaves", "dried sage", "rubbed sage"], .produce),
        CatalogEntry("chives", ["fresh chives", "chopped chives"], .produce),
        CatalogEntry("tarragon", ["fresh tarragon"], .produce),
        CatalogEntry("lemongrass", [], .produce),

        // Spices
        CatalogEntry("salt", ["kosher salt", "sea salt", "table salt", "fine salt", "flaky salt", "flaky sea salt", "coarse salt", "fine sea salt", "salt and pepper", "salt & pepper", "salt and black pepper"], .spices, staple: true),
        CatalogEntry("black pepper", ["pepper", "ground black pepper", "freshly ground black pepper", "cracked black pepper", "ground pepper", "black peppercorns", "peppercorns"], .spices, staple: true),
        CatalogEntry("white pepper", ["ground white pepper"], .spices, parent: "black pepper"),
        CatalogEntry("cinnamon", ["ground cinnamon", "cinnamon sticks", "cinnamon stick"], .spices, staple: true),
        CatalogEntry("nutmeg", ["ground nutmeg", "freshly grated nutmeg", "whole nutmeg"], .spices),
        CatalogEntry("cloves", ["ground cloves", "whole cloves"], .spices),
        CatalogEntry("allspice", ["ground allspice"], .spices),
        CatalogEntry("ginger powder", ["ground ginger", "dried ginger"], .spices),
        CatalogEntry("pumpkin pie spice", ["pumpkin spice", "mixed spice", "apple pie spice"], .spices),
        CatalogEntry("cardamom", ["ground cardamom", "cardamom pods"], .spices),
        CatalogEntry("cumin", ["ground cumin", "cumin seeds", "cumin seed"], .spices, staple: true),
        CatalogEntry("coriander", ["ground coriander", "coriander seeds", "coriander seed"], .spices),
        CatalogEntry("chili powder", ["chile powder", "chilli powder", "ancho chili powder"], .spices, staple: true),
        CatalogEntry("cayenne pepper", ["cayenne", "ground cayenne", "ground red pepper"], .spices),
        CatalogEntry("red pepper flakes", ["crushed red pepper", "crushed red pepper flakes", "chili flakes", "chilli flakes", "red chili flakes", "hot pepper flakes"], .spices, staple: true),
        CatalogEntry("paprika", ["sweet paprika", "hungarian paprika"], .spices, staple: true),
        CatalogEntry("smoked paprika", ["pimenton", "pimentón", "spanish paprika"], .spices, parent: "paprika"),
        CatalogEntry("turmeric", ["ground turmeric"], .spices),
        CatalogEntry("curry powder", ["madras curry powder"], .spices),
        CatalogEntry("garam masala", [], .spices),
        CatalogEntry("garlic powder", ["granulated garlic"], .spices, staple: true),
        CatalogEntry("onion powder", ["granulated onion"], .spices, staple: true),
        CatalogEntry("dried oregano", ["oregano", "mexican oregano", "fresh oregano"], .spices, staple: true),
        CatalogEntry("dried basil", [], .spices, parent: "basil"),
        CatalogEntry("dried parsley", ["parsley flakes"], .spices, parent: "parsley"),
        CatalogEntry("dried dill", [], .spices, parent: "dill"),
        CatalogEntry("italian seasoning", ["italian herbs", "herbes de provence", "mixed herbs", "dried italian seasoning"], .spices, staple: true),
        CatalogEntry("bay leaves", ["bay leaf", "dried bay leaves"], .spices),
        CatalogEntry("mustard powder", ["dry mustard", "ground mustard", "mustard seed", "mustard seeds"], .spices),
        CatalogEntry("celery salt", ["celery seed", "celery seeds"], .spices),
        CatalogEntry("old bay seasoning", ["old bay", "seafood seasoning"], .spices),
        CatalogEntry("cajun seasoning", ["creole seasoning", "blackening seasoning"], .spices),
        CatalogEntry("taco seasoning", ["fajita seasoning"], .spices),
        CatalogEntry("ranch seasoning", ["ranch dressing mix", "ranch seasoning mix", "dry ranch dressing mix"], .spices),
        CatalogEntry("everything bagel seasoning", [], .spices),
        CatalogEntry("chinese five spice", ["five spice powder", "five-spice powder", "five spice"], .spices),
        CatalogEntry("fennel seeds", ["fennel seed", "ground fennel"], .spices),
        CatalogEntry("caraway seeds", ["caraway"], .spices),
        CatalogEntry("saffron", ["saffron threads"], .spices),
        CatalogEntry("vanilla bean", ["vanilla beans", "vanilla bean paste"], .spices, parent: "vanilla extract"),
        CatalogEntry("espresso powder", ["instant espresso", "instant coffee", "instant espresso powder"], .spices),
        CatalogEntry("msg", ["accent", "monosodium glutamate"], .spices),
        CatalogEntry("bouillon", ["bouillon cubes", "bouillon cube", "chicken bouillon", "beef bouillon", "better than bouillon", "stock cubes", "stock cube", "chicken bouillon cubes"], .spices),

        // Condiments & oils
        CatalogEntry("olive oil", ["extra virgin olive oil", "extra-virgin olive oil", "evoo", "light olive oil"], .condiments, staple: true),
        CatalogEntry("vegetable oil", ["canola oil", "neutral oil", "cooking oil", "oil", "sunflower oil", "grapeseed oil", "corn oil", "peanut oil", "avocado oil", "safflower oil", "rapeseed oil"], .condiments, staple: true),
        CatalogEntry("coconut oil", ["virgin coconut oil", "refined coconut oil"], .condiments),
        CatalogEntry("sesame oil", ["toasted sesame oil"], .condiments),
        CatalogEntry("cooking spray", ["nonstick spray", "non-stick cooking spray", "pam", "baking spray"], .condiments),
        CatalogEntry("white vinegar", ["distilled white vinegar", "vinegar", "distilled vinegar"], .condiments, staple: true),
        CatalogEntry("apple cider vinegar", ["cider vinegar"], .condiments),
        CatalogEntry("balsamic vinegar", ["balsamic", "balsamic glaze"], .condiments),
        CatalogEntry("red wine vinegar", [], .condiments),
        CatalogEntry("white wine vinegar", ["champagne vinegar", "sherry vinegar"], .condiments),
        CatalogEntry("rice vinegar", ["rice wine vinegar", "seasoned rice vinegar"], .condiments),
        CatalogEntry("soy sauce", ["low sodium soy sauce", "low-sodium soy sauce", "tamari", "shoyu", "light soy sauce", "dark soy sauce", "coconut aminos"], .condiments),
        CatalogEntry("fish sauce", [], .condiments),
        CatalogEntry("oyster sauce", [], .condiments),
        CatalogEntry("hoisin sauce", ["hoisin"], .condiments),
        CatalogEntry("worcestershire sauce", ["worcestershire"], .condiments),
        CatalogEntry("hot sauce", ["tabasco", "frank's redhot", "franks red hot", "louisiana hot sauce", "cholula", "buffalo sauce"], .condiments),
        CatalogEntry("sriracha", ["sriracha sauce", "chili garlic sauce", "sambal oelek", "gochujang"], .condiments, parent: "hot sauce"),
        CatalogEntry("ketchup", ["catsup", "tomato ketchup"], .condiments),
        CatalogEntry("mustard", ["yellow mustard", "prepared mustard"], .condiments),
        CatalogEntry("dijon mustard", ["dijon", "whole grain mustard", "stone ground mustard", "grainy mustard"], .condiments, parent: "mustard"),
        CatalogEntry("mayonnaise", ["mayo", "hellmann's", "miracle whip", "kewpie mayo", "real mayonnaise"], .condiments),
        CatalogEntry("bbq sauce", ["barbecue sauce", "barbeque sauce"], .condiments),
        CatalogEntry("salsa", ["chunky salsa", "salsa verde", "pico de gallo"], .condiments),
        CatalogEntry("ranch dressing", ["ranch"], .condiments),
        CatalogEntry("italian dressing", ["vinaigrette", "salad dressing"], .condiments),
        CatalogEntry("relish", ["sweet relish", "pickle relish", "dill relish"], .condiments),
        CatalogEntry("pickles", ["dill pickles", "pickle", "bread and butter pickles", "cornichons", "pickle juice"], .condiments),
        CatalogEntry("capers", [], .condiments),
        CatalogEntry("olives", ["kalamata olives", "black olives", "green olives", "sliced olives", "sliced black olives"], .condiments),
        CatalogEntry("pesto", ["basil pesto"], .condiments),
        CatalogEntry("tahini", ["sesame paste"], .condiments),
        CatalogEntry("miso", ["miso paste", "white miso", "red miso"], .condiments),
        CatalogEntry("curry paste", ["red curry paste", "green curry paste", "thai curry paste", "yellow curry paste"], .condiments),
        CatalogEntry("horseradish", ["prepared horseradish"], .condiments),
        CatalogEntry("liquid smoke", [], .condiments),
        CatalogEntry("jam", ["jelly", "preserves", "strawberry jam", "apricot jam", "raspberry jam", "apricot preserves", "grape jelly", "marmalade", "fruit preserves"], .condiments),
        CatalogEntry("chili sauce", ["heinz chili sauce", "sweet chili sauce", "thai sweet chili sauce"], .condiments),
        CatalogEntry("teriyaki sauce", [], .condiments),
        CatalogEntry("enchilada sauce", ["red enchilada sauce", "green enchilada sauce"], .pantry),
        CatalogEntry("alfredo sauce", [], .pantry),

        // Pantry
        CatalogEntry("chicken broth", ["chicken stock", "low sodium chicken broth", "low-sodium chicken broth", "chicken bone broth", "reduced sodium chicken broth"], .pantry),
        CatalogEntry("beef broth", ["beef stock", "low sodium beef broth", "beef bone broth"], .pantry),
        CatalogEntry("vegetable broth", ["vegetable stock", "veggie broth", "veggie stock"], .pantry),
        CatalogEntry("rice", ["white rice", "long grain rice", "long-grain rice", "jasmine rice", "basmati rice", "cooked rice", "instant rice", "minute rice", "uncooked rice", "long grain white rice"], .pantry),
        CatalogEntry("brown rice", ["cooked brown rice"], .pantry, parent: "rice"),
        CatalogEntry("arborio rice", ["risotto rice", "carnaroli rice", "short grain rice", "sushi rice"], .pantry, parent: "rice"),
        CatalogEntry("wild rice", ["wild rice blend"], .pantry, parent: "rice"),
        CatalogEntry("quinoa", [], .pantry),
        CatalogEntry("couscous", ["israeli couscous", "pearl couscous"], .pantry),
        CatalogEntry("pasta", ["spaghetti", "penne", "rigatoni", "fettuccine", "linguine", "fusilli", "rotini", "farfalle", "bow tie pasta", "bowtie pasta", "orzo", "ziti", "angel hair", "angel hair pasta", "shells", "pasta shells", "elbow macaroni", "macaroni", "elbows", "tagliatelle", "pappardelle", "bucatini", "cavatappi", "gemelli", "orecchiette", "dried pasta", "penne pasta", "spaghetti noodles"], .pantry),
        CatalogEntry("egg noodles", ["wide egg noodles", "extra wide egg noodles"], .pantry, parent: "pasta"),
        CatalogEntry("lasagna noodles", ["lasagna sheets", "no-boil lasagna noodles", "oven-ready lasagna noodles"], .pantry, parent: "pasta"),
        CatalogEntry("rice noodles", ["rice vermicelli", "pad thai noodles", "glass noodles"], .pantry),
        CatalogEntry("ramen noodles", ["ramen", "instant ramen"], .pantry),
        CatalogEntry("soba noodles", ["udon noodles", "udon", "soba", "lo mein noodles", "chow mein noodles"], .pantry),
        CatalogEntry("tortellini", ["cheese tortellini", "ravioli", "gnocchi", "fresh pasta"], .pantry),
        CatalogEntry("bread crumbs", ["breadcrumbs", "panko", "panko breadcrumbs", "panko bread crumbs", "italian bread crumbs", "seasoned bread crumbs", "italian breadcrumbs", "dry bread crumbs"], .pantry),
        CatalogEntry("croutons", [], .pantry),
        CatalogEntry("crackers", ["ritz crackers", "saltines", "saltine crackers", "butter crackers"], .pantry),
        CatalogEntry("tortilla chips", ["corn chips", "fritos"], .pantry),
        CatalogEntry("potato chips", ["chips", "crisps"], .pantry),
        CatalogEntry("pretzels", [], .pantry),
        CatalogEntry("popcorn", ["popcorn kernels"], .pantry),
        CatalogEntry("black beans", ["canned black beans", "black bean"], .pantry),
        CatalogEntry("kidney beans", ["red kidney beans", "red beans", "dark red kidney beans"], .pantry),
        CatalogEntry("pinto beans", ["refried beans"], .pantry),
        CatalogEntry("cannellini beans", ["white beans", "great northern beans", "navy beans", "butter beans", "white kidney beans"], .pantry),
        CatalogEntry("chickpeas", ["garbanzo beans", "garbanzos", "chick peas", "canned chickpeas"], .pantry),
        CatalogEntry("lentils", ["red lentils", "green lentils", "brown lentils", "french lentils", "dried lentils"], .pantry),
        CatalogEntry("split peas", ["dried split peas", "yellow split peas", "green split peas"], .pantry),
        CatalogEntry("baked beans", ["pork and beans", "bush's baked beans"], .pantry),
        CatalogEntry("hummus", [], .pantry),
        CatalogEntry("cream of mushroom soup", ["condensed cream of mushroom soup", "cream of mushroom"], .pantry),
        CatalogEntry("cream of chicken soup", ["condensed cream of chicken soup", "cream of chicken", "cream of celery soup"], .pantry),
        CatalogEntry("tomato soup", ["condensed tomato soup"], .pantry),
        CatalogEntry("french fried onions", ["crispy fried onions", "fried onions", "french's fried onions"], .pantry),
        CatalogEntry("stuffing mix", ["stove top stuffing", "stuffing"], .pantry),
        CatalogEntry("cereal", ["corn flakes", "cornflakes", "rice krispies", "crispy rice cereal", "cheerios", "chex cereal", "chex"], .pantry),
        CatalogEntry("cake mix", ["yellow cake mix", "white cake mix", "chocolate cake mix", "boxed cake mix", "devil's food cake mix", "spice cake mix"], .baking),
        CatalogEntry("brownie mix", [], .baking),
        CatalogEntry("pudding mix", ["instant pudding", "instant pudding mix", "vanilla pudding mix", "chocolate pudding mix", "instant vanilla pudding"], .baking),
        CatalogEntry("jello", ["jell-o", "gelatin dessert", "strawberry jello", "flavored gelatin"], .baking),
        CatalogEntry("marshmallows", ["mini marshmallows", "marshmallow", "marshmallow creme", "marshmallow fluff"], .baking),
        CatalogEntry("caramels", ["caramel sauce", "caramel candies", "dulce de leche", "caramel"], .baking),
        CatalogEntry("pie crust", ["pie crusts", "refrigerated pie crust", "pie shell", "unbaked pie crust", "pastry crust", "pie dough", "shortcrust pastry", "9-inch pie crust", "deep dish pie crust"], .frozen),
        CatalogEntry("puff pastry", ["frozen puff pastry", "puff pastry sheets"], .frozen),
        CatalogEntry("phyllo dough", ["filo dough", "phyllo", "filo pastry"], .frozen),
        CatalogEntry("crescent rolls", ["refrigerated crescent rolls", "crescent roll dough", "crescent dough"], .dairy),
        CatalogEntry("biscuit dough", ["refrigerated biscuits", "canned biscuits", "pillsbury biscuits", "refrigerated biscuit dough"], .dairy),
        CatalogEntry("pizza dough", ["refrigerated pizza dough", "pizza crust"], .dairy),
        CatalogEntry("tortillas", ["flour tortillas", "corn tortillas", "tortilla", "taco shells", "wraps"], .bakery),
        CatalogEntry("bread", ["white bread", "sandwich bread", "sliced bread", "bread slices", "sourdough", "sourdough bread", "french bread", "italian bread", "baguette", "crusty bread", "whole wheat bread", "texas toast", "brioche", "challah", "ciabatta"], .bakery),
        CatalogEntry("hamburger buns", ["burger buns", "buns", "brioche buns", "slider buns", "hot dog buns", "hoagie rolls", "sub rolls", "kaiser rolls", "dinner rolls", "rolls"], .bakery),
        CatalogEntry("english muffins", ["english muffin"], .bakery),
        CatalogEntry("bagels", ["bagel"], .bakery),
        CatalogEntry("pita bread", ["pita", "pitas", "naan", "flatbread", "naan bread"], .bakery),
        CatalogEntry("cornbread mix", ["jiffy corn muffin mix", "jiffy mix", "corn muffin mix"], .baking),
        CatalogEntry("pancake mix", ["bisquick", "baking mix", "biscuit mix"], .baking),
        CatalogEntry("frozen vegetables", ["mixed vegetables", "frozen mixed vegetables", "frozen veggies", "stir fry vegetables", "frozen stir-fry vegetables"], .frozen),
        CatalogEntry("hash browns", ["frozen hash browns", "shredded hash browns", "tater tots", "frozen potatoes", "frozen french fries", "french fries"], .frozen),
        CatalogEntry("frozen fruit", ["frozen strawberries", "frozen mango", "frozen peaches"], .frozen),
        CatalogEntry("tofu", ["firm tofu", "extra firm tofu", "extra-firm tofu", "silken tofu"], .produce),
        CatalogEntry("tempeh", [], .produce),
        CatalogEntry("nutritional yeast", [], .pantry),
        CatalogEntry("seaweed", ["nori", "nori sheets", "kombu", "wakame"], .pantry),
        CatalogEntry("kimchi", [], .produce),
        CatalogEntry("sauerkraut", [], .condiments),
        CatalogEntry("water chestnuts", ["sliced water chestnuts", "canned water chestnuts"], .pantry),
        CatalogEntry("bamboo shoots", [], .pantry),
        CatalogEntry("artichoke hearts", ["canned artichoke hearts", "marinated artichoke hearts", "artichokes"], .pantry),
        CatalogEntry("roasted red peppers", ["jarred roasted red peppers", "roasted peppers", "piquillo peppers"], .pantry),
        CatalogEntry("beets", ["beet", "beetroot", "canned beets", "roasted beets"], .produce),
        CatalogEntry("radishes", ["radish"], .produce),
        CatalogEntry("turnips", ["turnip", "rutabaga", "parsnips", "parsnip"], .produce),
        CatalogEntry("fennel", ["fennel bulb"], .produce),
        CatalogEntry("bok choy", ["baby bok choy", "pak choi"], .produce),
        CatalogEntry("bean sprouts", ["sprouts", "mung bean sprouts"], .produce),
        CatalogEntry("snap peas", ["sugar snap peas", "snow peas"], .produce),
        CatalogEntry("edamame", ["shelled edamame"], .frozen),
        CatalogEntry("okra", [], .produce),
        CatalogEntry("plantains", ["plantain"], .produce),
        CatalogEntry("applesauce", ["unsweetened applesauce", "apple sauce"], .pantry),
        CatalogEntry("cranberry sauce", ["whole berry cranberry sauce", "jellied cranberry sauce"], .pantry),
        CatalogEntry("pie filling", ["cherry pie filling", "apple pie filling", "blueberry pie filling"], .baking),
        CatalogEntry("mandarin oranges", ["canned mandarin oranges"], .pantry),
        CatalogEntry("canned peaches", ["peach slices in juice", "sliced peaches"], .pantry),
        CatalogEntry("maraschino cherries", ["cocktail cherries"], .pantry),

        // Beverages
        CatalogEntry("water", ["warm water", "cold water", "hot water", "boiling water", "ice water", "lukewarm water", "ice"], .beverages, staple: true),
        CatalogEntry("coffee", ["brewed coffee", "strong coffee", "cold brew", "espresso", "ground coffee", "coffee beans"], .beverages),
        CatalogEntry("tea", ["black tea", "green tea", "tea bags", "earl grey", "chai"], .beverages),
        CatalogEntry("white wine", ["dry white wine", "sauvignon blanc", "pinot grigio", "chardonnay", "white cooking wine"], .beverages),
        CatalogEntry("red wine", ["dry red wine", "cabernet", "merlot", "pinot noir", "red cooking wine", "chianti"], .beverages),
        CatalogEntry("beer", ["lager", "ale", "stout", "guinness", "light beer", "pale ale"], .beverages),
        CatalogEntry("bourbon", ["whiskey", "whisky", "rye whiskey", "scotch"], .beverages),
        CatalogEntry("rum", ["dark rum", "spiced rum", "white rum", "light rum"], .beverages),
        CatalogEntry("vodka", [], .beverages),
        CatalogEntry("tequila", ["mezcal"], .beverages),
        CatalogEntry("brandy", ["cognac"], .beverages),
        CatalogEntry("sherry", ["dry sherry", "marsala", "marsala wine", "port", "vermouth", "dry vermouth", "madeira"], .beverages),
        CatalogEntry("liqueur", ["kahlua", "coffee liqueur", "amaretto", "grand marnier", "triple sec", "cointreau", "baileys", "irish cream", "limoncello", "orange liqueur"], .beverages),
        CatalogEntry("apple juice", ["apple cider", "sparkling cider"], .beverages),
        CatalogEntry("cranberry juice", [], .beverages),
        CatalogEntry("pineapple juice", [], .beverages),
        CatalogEntry("tomato juice", ["v8", "vegetable juice", "clamato"], .beverages),
        CatalogEntry("soda", ["cola", "coke", "coca-cola", "sprite", "7up", "ginger ale", "club soda", "seltzer", "sparkling water", "tonic water", "dr pepper", "root beer", "lemon-lime soda"], .beverages),
        CatalogEntry("almond milk", ["oat milk", "soy milk", "cashew milk", "plant milk", "non-dairy milk", "unsweetened almond milk"], .dairy, parent: "milk"),
        CatalogEntry("lemonade", ["frozen lemonade concentrate"], .beverages),
        CatalogEntry("orange juice concentrate", ["frozen orange juice concentrate"], .frozen),
    ]

    static let byName: [String: CatalogEntry] = {
        var map: [String: CatalogEntry] = [:]
        for entry in entries { map[entry.name] = entry }
        return map
    }()

    /// Normalised alias → canonical name. Built with the same normaliser the
    /// matcher uses on recipe text, so both sides always agree on spelling,
    /// plurals and hyphens.
    static let byAlias: [String: String] = {
        var map: [String: String] = [:]
        for entry in entries {
            for alias in [entry.name] + entry.aliases {
                let key = IngredientKey.normalizedPhrase(alias)
                if !key.isEmpty, map[key] == nil { map[key] = entry.name }
            }
        }
        // The canonical spelling of every entry wins over a same-spelled
        // alias of another entry.
        for entry in entries {
            map[IngredientKey.normalizedPhrase(entry.name)] = entry.name
        }
        return map
    }()

    /// Aliases sorted longest first, for finding a known ingredient inside a
    /// longer description ("boneless skinless chicken thighs, trimmed").
    static let aliasesByLength: [(key: String, name: String)] = {
        byAlias.map { (key: $0.key, name: $0.value) }
            .sorted { a, b in
                let wa = a.key.split(separator: " ").count
                let wb = b.key.split(separator: " ").count
                if wa != wb { return wa > wb }
                return a.key.count > b.key.count
            }
    }()

    static func entry(for key: String) -> CatalogEntry? {
        byName[key]
    }

    static var defaultStaples: [String] {
        entries.filter(\.staple).map(\.name)
    }

    /// Names to offer as someone types in the pantry.
    static func suggestions(matching text: String, limit: Int = 8) -> [CatalogEntry] {
        let needle = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }
        var seen = Set<String>()
        var starts: [CatalogEntry] = []
        var contains: [CatalogEntry] = []
        for entry in entries {
            let names = [entry.name] + entry.aliases
            if names.contains(where: { $0.hasPrefix(needle) }) {
                if seen.insert(entry.name).inserted { starts.append(entry) }
            } else if names.contains(where: { $0.contains(needle) }) {
                if seen.insert(entry.name).inserted { contains.append(entry) }
            }
        }
        return Array((starts + contains).prefix(limit))
    }

    /// A short list for "add the usual things" in a fresh pantry.
    static let commonKitchen: [String] = [
        "all-purpose flour", "granulated sugar", "brown sugar", "baking soda", "baking powder",
        "vanilla extract", "salt", "black pepper", "olive oil", "vegetable oil", "butter", "eggs",
        "milk", "garlic", "onion", "potatoes", "carrots", "celery", "lemon", "rice", "pasta",
        "chicken broth", "canned tomatoes", "tomato paste", "soy sauce", "white vinegar",
        "apple cider vinegar", "honey", "mayonnaise", "ketchup", "dijon mustard", "hot sauce",
        "cheddar cheese", "parmesan", "cinnamon", "cumin", "chili powder", "paprika",
        "dried oregano", "italian seasoning", "garlic powder", "onion powder", "red pepper flakes",
        "bay leaves", "cornstarch", "chocolate chips", "rolled oats", "peanut butter", "bread",
        "tortillas", "black beans", "chickpeas", "frozen peas", "corn", "bacon", "ground beef",
        "chicken breast", "frozen vegetables",
    ]
}
