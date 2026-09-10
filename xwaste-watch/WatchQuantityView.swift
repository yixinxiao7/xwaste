import SwiftUI
import CoreData

/// watchOS has no `Stepper`, and cramming tap targets into rows invites
/// accidental check-offs — so quantity gets its own screen with two large
/// buttons. Decrement-to-zero deletes the row, the same rule as everywhere
/// else, and reports back so the list can confirm it in the same style rather
/// than asking first: the row is recoverable from the phone's Move to Shopping
/// List.
struct WatchQuantityView: View {
    @ObservedObject var item: GroceryItem
    /// Called with the removed item's name once a decrement reaches zero. The
    /// screen does not confirm it itself — the row is gone, so this view is on
    /// its way out and the list owns the message.
    let onRemoved: (String) -> Void

    @Environment(\.managedObjectContext) private var context

    var body: some View {
        VStack(spacing: 8) {
            if item.isDeleted || item.managedObjectContext == nil {
                // Deleted out from under us; the pop is already in flight.
                ProgressView()
            } else {
                Text("\(item.quantity)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("quantity-value")
                HStack(spacing: 12) {
                    adjustButton(systemImage: "minus", delta: -1, label: "Decrease quantity")
                        .accessibilityIdentifier("quantity-decrement")
                    adjustButton(systemImage: "plus", delta: 1, label: "Increase quantity")
                        .accessibilityIdentifier("quantity-increment")
                }
            }
        }
        .navigationTitle(item.isDeleted ? "" : item.displayName)
    }

    private func adjustButton(systemImage: String, delta: Int64, label: String) -> some View {
        Button {
            adjust(by: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel(label)
    }

    private func adjust(by delta: Int64) {
        let removed = item.quantity + delta <= 0
        let name = item.displayName
        GroceryStore.adjustQuantity(item, by: delta, context: context)
        if removed { onRemoved(name) }
    }
}
