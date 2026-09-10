import SwiftUI
import CoreData

/// One page of the watch app. Both pages share this body: the same
/// `CategorySection` grouping, the same fixed category order, the same
/// quantity path. Only the shopping list gets a check-off affordance — the
/// watch is a remote for the list, not a second editor, so there is no add,
/// rename, recategorize, share, or delete control on either page.
struct WatchListView: View {
    private let household: Household
    private let location: ItemLocation
    private let isPerformingFirstImport: Bool

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<GroceryItem>

    @State private var confirmation: WatchConfirmation?
    @State private var confirmationDismissTask: Task<Void, Never>?
    /// Pushed programmatically rather than with a row `NavigationLink`: on
    /// watchOS a link inside a row claims the *whole* row's tap, which would
    /// let the quantity control steal the check-off the spec makes primary.
    @State private var quantityItemID: NSManagedObjectID?

    init(household: Household, location: ItemLocation, isPerformingFirstImport: Bool) {
        self.household = household
        self.location = location
        self.isPerformingFirstImport = isPerformingFirstImport
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "locationRawValue == %@ AND household == %@",
            location.rawValue, household
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _items = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var isShoppingList: Bool { location == .shoppingList }

    var body: some View {
        List {
            ForEach(CategorySection.sections(from: items)) { section in
                Section(section.category.displayName) {
                    ForEach(section.items, id: \.objectID) { item in
                        WatchItemRow(item: item,
                                     showsCheckOff: isShoppingList,
                                     onCheckOff: { checkOff(item) },
                                     onAdjustQuantity: { quantityItemID = item.objectID })
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty { emptyState }
        }
        .navigationTitle(isShoppingList ? "Shopping List" : "At Home")
        .navigationDestination(item: $quantityItemID) { id in
            if let item = try? context.existingObject(with: id) as? GroceryItem {
                WatchQuantityView(item: item, onRemoved: itemWasRemoved)
            }
        }
        .fullScreenCover(item: $confirmation) { confirmation in
            WatchConfirmationView(confirmation: confirmation,
                                  onUndo: { performUndo($0) },
                                  onDismiss: dismissConfirmation)
        }
        // Leaving the page dismisses the confirmation; expiry changes nothing.
        .onDisappear(perform: dismissConfirmation)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isPerformingFirstImport {
            EmptyStateView(systemImage: "arrow.triangle.2.circlepath",
                           title: "Syncing",
                           message: "Getting your household's items from iCloud.")
                .accessibilityIdentifier("syncing-state")
        } else if isShoppingList {
            EmptyStateView(systemImage: "cart",
                           title: "Nothing to buy",
                           message: "Add items on your iPhone and they will appear here.")
                .accessibilityIdentifier("empty-shopping-list")
        } else {
            EmptyStateView(systemImage: "house",
                           title: "Nothing at home yet",
                           message: "Items you check off land here.")
                .accessibilityIdentifier("empty-inventory")
        }
    }

    /// Single tap, no confirmation dialog — the undo screen is the safety net,
    /// exactly as the phone's banner is.
    private func checkOff(_ item: GroceryItem) {
        let name = item.displayName
        guard let undo = GroceryStore.checkOff(item, context: context) else { return }
        show(WatchConfirmation(message: "Checked off \(name)", undo: undo))
    }

    /// Decrement-to-zero on the quantity screen: pop back and say what went,
    /// in the same style as a check-off — but with nothing to undo, because the
    /// permanent recovery for a used-up item is the phone.
    private func itemWasRemoved(_ name: String) {
        quantityItemID = nil
        show(WatchConfirmation(message: "Removed \(name)", undo: nil))
    }

    private func performUndo(_ undo: CheckOffUndo) {
        switch GroceryStore.undoCheckOff(undo, context: context) {
        case .reversed:
            dismissConfirmation()
        case .changedElsewhere:
            show(WatchConfirmation(message: "\(undo.name) was changed elsewhere and left as-is",
                                   undo: nil))
        }
    }

    private func show(_ newConfirmation: WatchConfirmation) {
        confirmation = newConfirmation
        confirmationDismissTask?.cancel()
        confirmationDismissTask = Task {
            try? await Task.sleep(for: LaunchSupport.confirmationDuration)
            guard !Task.isCancelled else { return }
            confirmation = nil
        }
    }

    private func dismissConfirmation() {
        confirmationDismissTask?.cancel()
        confirmation = nil
    }
}

/// The row's bulk checks off; the narrow trailing control is the only way to
/// reach the quantity screen, so a deliberate quantity change can never be
/// mistaken for the cheap primary action.
///
/// Both controls are `.bordered` buttons carrying the row's own background,
/// rather than plain content inside a list row: on watchOS a `.plain` button in
/// a `List` row never receives the tap — the cell swallows it — so the row
/// would silently do nothing.
struct WatchItemRow: View {
    @ObservedObject var item: GroceryItem
    let showsCheckOff: Bool
    let onCheckOff: () -> Void
    let onAdjustQuantity: () -> Void

    var body: some View {
        Group {
            if showsCheckOff {
                HStack(spacing: 4) {
                    Button(action: onCheckOff) {
                        label
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("checkoff-\(item.displayName)")
                    .accessibilityLabel("Check off \(item.displayName)")

                    Button(action: onAdjustQuantity) {
                        Image(systemName: "plusminus")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityIdentifier("quantity-\(item.displayName)")
                    .accessibilityLabel("Adjust quantity for \(item.displayName)")
                }
            } else {
                // At Home has no check-off, so the whole row is the quantity path.
                Button(action: onAdjustQuantity) {
                    label
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quantity-\(item.displayName)")
                .accessibilityLabel("Adjust quantity for \(item.displayName)")
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
    }

    private var label: some View {
        HStack {
            Text(item.displayName)
                .lineLimit(2)
            Spacer(minLength: 4)
            Text("\(item.quantity)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
