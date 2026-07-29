import Foundation

/// Deterministic, offline categorization over a compiled-in keyword table.
/// No AI, no ML, no network, no I/O — this must stay a pure function over the
/// static table even after sync exists. That is a user requirement, not a
/// performance choice.
nonisolated enum CategoryClassifier {

    /// Matching order:
    /// 1. Exact whole-name match of the normalized name.
    /// 2. Among keywords appearing in the name **on word boundaries**, the one
    ///    whose last character falls latest in the name (grocery names are
    ///    modifier-then-head-noun: "chocolate milk" is milk, "milk chocolate"
    ///    is candy). Same end position → longer keyword wins (`ice cream` beats
    ///    `cream`), then earlier category order. Never depends on dictionary
    ///    iteration order.
    /// 3. `.other`.
    static func classify(_ rawName: String) -> GroceryCategory {
        let name = GroceryItem.normalize(rawName)
        guard !name.isEmpty else { return .other }

        if let exact = keywordTable[name] { return exact }

        let padded = " " + name + " "
        var best: (end: Int, length: Int, order: Int, category: GroceryCategory)?
        for (keyword, category) in keywordTable {
            let paddedKeyword = " " + keyword + " "
            var searchStart = padded.startIndex
            var lastEnd: Int?
            while let range = padded.range(of: paddedKeyword, range: searchStart..<padded.endIndex) {
                // Index of the keyword's final character within `name`.
                lastEnd = padded.distance(from: padded.startIndex, to: range.upperBound) - 2
                searchStart = padded.index(after: range.lowerBound)
            }
            guard let end = lastEnd else { continue }
            let candidate = (end: end, length: keyword.count, order: category.sortOrder, category: category)
            guard let current = best else { best = candidate; continue }
            if candidate.end > current.end
                || (candidate.end == current.end && candidate.length > current.length)
                || (candidate.end == current.end && candidate.length == current.length
                    && candidate.order < current.order) {
                best = candidate
            }
        }
        return best?.category ?? .other
    }

    /// Keyed on **normalized** strings: `classify` normalizes its input, and
    /// normalization folds a trailing plural, so a raw key of "asparagus"
    /// (which normalizes to "asparagu") could never match. Every natural key is
    /// run through `GroceryItem.normalize` here instead of hand-writing folded
    /// keys, and a collision after folding is an authoring bug caught at once.
    static let keywordTable: [String: GroceryCategory] = {
        var table = [String: GroceryCategory](minimumCapacity: naturalKeys.count)
        for (key, category) in naturalKeys {
            let folded = GroceryItem.normalize(key)
            assert(table[folded] == nil,
                   "Keyword table collision: '\(key)' folds to '\(folded)', which is already present")
            table[folded] = category
        }
        return table
    }()

    /// Seed terms in their natural spelling. Singular keys also match s-plural
    /// inputs (the fold is symmetric); y-plurals ("berries") need both spellings
    /// because the conservative fold cannot map "berries" onto "berry".
    private static let naturalKeys: [(String, GroceryCategory)] = [
        // Produce
        ("broccoli", .produce), ("spinach", .produce), ("lettuce", .produce),
        ("kale", .produce), ("arugula", .produce), ("cabbage", .produce),
        ("bok choy", .produce), ("carrot", .produce), ("potato", .produce),
        ("onion", .produce), ("scallion", .produce), ("garlic", .produce),
        ("ginger", .produce), ("tomato", .produce), ("cucumber", .produce),
        ("zucchini", .produce), ("squash", .produce), ("pumpkin", .produce),
        ("pepper", .produce), ("bell pepper", .produce), ("jalapeno", .produce),
        ("celery", .produce), ("asparagus", .produce), ("mushroom", .produce),
        ("corn", .produce), ("avocado", .produce), ("cauliflower", .produce),
        ("eggplant", .produce), ("radish", .produce), ("beet", .produce),
        ("turnip", .produce), ("leek", .produce), ("shallot", .produce),
        ("brussels sprouts", .produce), ("green bean", .produce), ("pea", .produce),
        ("apple", .produce), ("banana", .produce), ("orange", .produce),
        ("grapefruit", .produce), ("lemon", .produce), ("lime", .produce),
        ("grape", .produce), ("strawberry", .produce), ("strawberries", .produce),
        ("blueberry", .produce), ("blueberries", .produce), ("raspberry", .produce),
        ("raspberries", .produce), ("blackberry", .produce), ("blackberries", .produce),
        ("cherry", .produce), ("cherries", .produce), ("peach", .produce),
        ("pear", .produce), ("plum", .produce), ("mango", .produce),
        ("pineapple", .produce), ("watermelon", .produce), ("cantaloupe", .produce),
        ("melon", .produce), ("kiwi", .produce), ("cilantro", .produce),
        ("parsley", .produce), ("basil", .produce), ("mint", .produce),
        ("thyme", .produce), ("rosemary", .produce), ("salad", .produce),

        // Dairy & Eggs
        ("milk", .dairyAndEggs), ("cream", .dairyAndEggs), ("half and half", .dairyAndEggs),
        ("yogurt", .dairyAndEggs), ("butter", .dairyAndEggs), ("cheese", .dairyAndEggs),
        ("cheddar", .dairyAndEggs), ("mozzarella", .dairyAndEggs), ("parmesan", .dairyAndEggs),
        ("feta", .dairyAndEggs), ("egg", .dairyAndEggs), ("buttermilk", .dairyAndEggs),
        ("kefir", .dairyAndEggs), ("ghee", .dairyAndEggs),

        // Meat & Seafood
        ("chicken", .meatAndSeafood), ("beef", .meatAndSeafood), ("pork", .meatAndSeafood),
        ("turkey", .meatAndSeafood), ("ham", .meatAndSeafood), ("bacon", .meatAndSeafood),
        ("sausage", .meatAndSeafood), ("steak", .meatAndSeafood), ("lamb", .meatAndSeafood),
        ("veal", .meatAndSeafood), ("salami", .meatAndSeafood), ("pepperoni", .meatAndSeafood),
        ("prosciutto", .meatAndSeafood), ("hot dog", .meatAndSeafood), ("meatball", .meatAndSeafood),
        ("rib", .meatAndSeafood), ("fish", .meatAndSeafood), ("salmon", .meatAndSeafood),
        ("tuna", .meatAndSeafood), ("shrimp", .meatAndSeafood), ("crab", .meatAndSeafood),
        ("lobster", .meatAndSeafood), ("cod", .meatAndSeafood), ("tilapia", .meatAndSeafood),
        ("halibut", .meatAndSeafood), ("scallop", .meatAndSeafood), ("sardine", .meatAndSeafood),

        // Bakery
        ("bread", .bakery), ("bagel", .bakery), ("baguette", .bakery),
        ("croissant", .bakery), ("muffin", .bakery), ("roll", .bakery),
        ("bun", .bakery), ("tortilla", .bakery), ("pita", .bakery),
        ("naan", .bakery), ("donut", .bakery), ("doughnut", .bakery),
        ("cake", .bakery), ("cupcake", .bakery), ("pancake", .bakery),
        ("pie", .bakery), ("brownie", .bakery), ("sourdough", .bakery),
        ("biscuit", .bakery), ("scone", .bakery), ("pastry", .bakery),
        ("loaf", .bakery),

        // Frozen
        ("ice cream", .frozen), ("popsicle", .frozen), ("sorbet", .frozen),
        ("gelato", .frozen), ("frozen", .frozen), ("pizza", .frozen),
        ("waffle", .frozen), ("fish sticks", .frozen),

        // Pantry
        ("rice", .pantry), ("pasta", .pantry), ("spaghetti", .pantry),
        ("macaroni", .pantry), ("noodle", .pantry), ("flour", .pantry),
        ("sugar", .pantry), ("salt", .pantry), ("black pepper", .pantry),
        ("olive oil", .pantry), ("oil", .pantry), ("vinegar", .pantry),
        ("sauce", .pantry), ("salsa", .pantry), ("ketchup", .pantry),
        ("mustard", .pantry), ("mayonnaise", .pantry), ("mayo", .pantry),
        ("relish", .pantry), ("honey", .pantry), ("syrup", .pantry),
        ("jam", .pantry), ("jelly", .pantry), ("peanut butter", .pantry),
        ("almond butter", .pantry), ("cereal", .pantry), ("oats", .pantry),
        ("oatmeal", .pantry), ("granola", .pantry), ("bean", .pantry),
        ("lentil", .pantry), ("chickpea", .pantry), ("quinoa", .pantry),
        ("broth", .pantry), ("stock", .pantry), ("soup", .pantry),
        ("spice", .pantry), ("cinnamon", .pantry), ("cumin", .pantry),
        ("paprika", .pantry), ("oregano", .pantry), ("vanilla", .pantry),
        ("baking soda", .pantry), ("baking powder", .pantry), ("yeast", .pantry),
        ("cornstarch", .pantry), ("breadcrumb", .pantry), ("crouton", .pantry),
        ("mix", .pantry), ("molasses", .pantry), ("couscous", .pantry),
        ("hummus", .pantry), ("tahini", .pantry), ("coconut milk", .pantry),
        ("paste", .pantry),

        // Beverages
        ("water", .beverages), ("juice", .beverages), ("soda", .beverages),
        ("cola", .beverages), ("coffee", .beverages), ("tea", .beverages),
        ("beer", .beverages), ("wine", .beverages), ("kombucha", .beverages),
        ("lemonade", .beverages), ("cider", .beverages), ("seltzer", .beverages),
        ("smoothie", .beverages), ("drink", .beverages), ("bar", .beverages),

        // Snacks
        ("chips", .snacks), ("crackers", .snacks), ("pretzels", .snacks),
        ("popcorn", .snacks), ("cookie", .snacks), ("candy", .snacks),
        ("candies", .snacks), ("chocolate", .snacks), ("gum", .snacks),
        ("trail mix", .snacks), ("nuts", .snacks), ("almond", .snacks),
        ("peanut", .snacks), ("cashew", .snacks), ("pistachio", .snacks),
        ("walnut", .snacks), ("pecan", .snacks), ("granola bar", .snacks),
        ("protein bar", .snacks), ("chocolate bar", .snacks), ("jerky", .snacks),
        ("snack", .snacks),

        // Household Goods
        ("paper towel", .householdGoods), ("toilet paper", .householdGoods),
        ("paper", .householdGoods), ("napkin", .householdGoods),
        ("tissue", .householdGoods), ("detergent", .householdGoods),
        ("soap", .householdGoods), ("shampoo", .householdGoods),
        ("conditioner", .householdGoods), ("toothpaste", .householdGoods),
        ("toothbrush", .householdGoods), ("deodorant", .householdGoods),
        ("trash bag", .householdGoods), ("garbage bag", .householdGoods),
        ("sponge", .householdGoods), ("cleaner", .householdGoods),
        ("bleach", .householdGoods), ("foil", .householdGoods),
        ("plastic wrap", .householdGoods), ("parchment paper", .householdGoods),
        ("battery", .householdGoods), ("batteries", .householdGoods),
        ("lightbulb", .householdGoods), ("candle", .householdGoods),
        ("floss", .householdGoods), ("razor", .householdGoods),
        ("lotion", .householdGoods), ("sunscreen", .householdGoods),
        ("towel", .householdGoods),
    ]
}

#if DEBUG && canImport(Playgrounds)
import Playgrounds

#Playground {
    // Spec scenarios for classification (item-categorization spec + task 4.5).
    let cases: [(String, GroceryCategory)] = [
        ("Broccoli", .produce),
        ("organic baby spinach", .produce),
        ("2% milk", .dairyAndEggs),
        ("Zorbex", .other),
        // Rightmost match decides compound names.
        ("potato chips", .snacks),
        ("apple juice", .beverages),
        ("chocolate milk", .dairyAndEggs),
        ("milk chocolate", .snacks),
        // Same end position: longer keyword wins ("ice cream" beats "cream").
        ("vanilla ice cream", .frozen),
        // Word boundaries: "bar" must not match inside "barbecue".
        ("barbecue sauce", .pantry),
        // Folded keys stay reachable.
        ("Asparagus", .produce),
        ("Tortilla Chips", .snacks),
    ]
    for (name, expected) in cases {
        let got = CategoryClassifier.classify(name)
        assert(got == expected, "\(name): expected \(expected), got \(got)")
    }

    // Normalization scenarios.
    assert(GroceryItem.normalize("  broccoli  ") == GroceryItem.normalize("Broccoli"))
    assert(GroceryItem.normalize("onions") == GroceryItem.normalize("onion"))
    assert(GroceryItem.normalize("green onion") != GroceryItem.normalize("onion"))
}
#endif
