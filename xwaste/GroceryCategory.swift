import Foundation

/// The fixed category set, in display order. The case is `householdGoods`, not
/// `household`, so it can never be confused with the `Household` entity — the
/// user-facing name is still "Household".
nonisolated enum GroceryCategory: String, CaseIterable {
    case produce
    case dairyAndEggs
    case meatAndSeafood
    case bakery
    case frozen
    case pantry
    case beverages
    case snacks
    case householdGoods
    case other

    var displayName: String {
        switch self {
        case .produce: "Produce"
        case .dairyAndEggs: "Dairy & Eggs"
        case .meatAndSeafood: "Meat & Seafood"
        case .bakery: "Bakery"
        case .frozen: "Frozen"
        case .pantry: "Pantry"
        case .beverages: "Beverages"
        case .snacks: "Snacks"
        case .householdGoods: "Household"
        case .other: "Other"
        }
    }

    var sfSymbol: String {
        switch self {
        case .produce: "carrot"
        case .dairyAndEggs: "cup.and.saucer"
        case .meatAndSeafood: "fish"
        case .bakery: "birthday.cake"
        case .frozen: "snowflake"
        case .pantry: "cabinet"
        case .beverages: "mug"
        case .snacks: "popcorn"
        case .householdGoods: "house"
        case .other: "shippingbox"
        }
    }

    /// Fixed sort position; `.other` is always last because it is the final case.
    var sortOrder: Int { Self.allCases.firstIndex(of: self)! }
}
