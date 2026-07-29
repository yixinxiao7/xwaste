import CoreData

nonisolated enum ItemLocation: String {
    case shoppingList
    case atHome
}

@objc(GroceryItem)
nonisolated final class GroceryItem: NSManagedObject {
    @NSManaged var name: String?
    @NSManaged var normalizedName: String?
    @NSManaged var quantity: Int64
    @NSManaged var categoryRawValue: String?
    @NSManaged var locationRawValue: String?
    @NSManaged var categoryIsManual: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
}

extension GroceryItem {
    @nonobjc static func fetchRequest() -> NSFetchRequest<GroceryItem> {
        NSFetchRequest<GroceryItem>(entityName: "GroceryItem")
    }

    var displayName: String { name ?? "" }

    var category: GroceryCategory {
        get { categoryRawValue.flatMap(GroceryCategory.init(rawValue:)) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var location: ItemLocation {
        get { locationRawValue.flatMap(ItemLocation.init(rawValue:)) ?? .shoppingList }
        set { locationRawValue = newValue.rawValue }
    }
}

extension GroceryItem {
    /// trim → collapse whitespace → lowercase → strip punctuation → fold trailing plural.
    /// Applied identically when storing a name and when looking one up, so the
    /// imperfect plural fold is harmless: "asparagus" folds to "asparagu" on both
    /// sides. Only exact equality of normalized names ever counts as a match.
    nonisolated static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let stripped = String(String.UnicodeScalarView(
            lowered.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) }
        ))
        var words = stripped.split(whereSeparator: \.isWhitespace).map(String.init)
        if let last = words.last {
            words[words.count - 1] = foldTrailingPlural(last)
        }
        return words.joined(separator: " ")
    }

    /// Conservative suffix rule, not a real stemmer: drop one trailing "s" unless
    /// the word ends in "ss" ("swiss") or is just "s" itself.
    private nonisolated static func foldTrailingPlural(_ word: String) -> String {
        guard word.count >= 2, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// The only way to construct an item: derives `normalizedName` and classifies
    /// the category, so no caller can create an inconsistent record.
    @discardableResult
    static func create(name: String,
                       quantity: Int64 = 1,
                       location: ItemLocation,
                       household: Household,
                       in context: NSManagedObjectContext) -> GroceryItem {
        let item = GroceryItem(context: context)
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.normalizedName = normalize(name)
        item.quantity = max(1, quantity)
        item.category = CategoryClassifier.classify(name)
        item.categoryIsManual = false
        item.location = location
        item.createdAt = Date()
        item.household = household
        return item
    }
}
