import SwiftUI
import CoreData

/// One category's slice of a fetch. Both screens build their sections through
/// `sections(from:)` so they can never disagree on grouping or order.
struct CategorySection: Identifiable {
    let category: GroceryCategory
    let items: [GroceryItem]

    var id: GroceryCategory { category }

    /// Groups items into sections in the fixed category order, omitting empty
    /// categories. Items keep the order they arrive in — every fetch in the app
    /// sorts by `createdAt` ascending, so new items append to the bottom of a
    /// section rather than reordering rows the user is looking at.
    static func sections(from items: some Sequence<GroceryItem>) -> [CategorySection] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return GroceryCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return CategorySection(category: category, items: items)
        }
    }
}

/// Shared row: name, quantity, and an inline stepper that adjusts in place
/// without navigation. The optional check-off control only appears on the
/// shopping list.
struct ItemRowView: View {
    @ObservedObject var item: GroceryItem
    var onCheckOff: (() -> Void)?
    let onAdjust: (Int64) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let onCheckOff {
                Button(action: onCheckOff) {
                    Image(systemName: "circle")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Check off \(item.displayName)")
            }
            Text(item.displayName)
            Spacer()
            Text("\(item.quantity)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("Quantity for \(item.displayName)",
                    onIncrement: { onAdjust(1) },
                    onDecrement: { onAdjust(-1) })
                .labelsHidden()
                .fixedSize()
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
