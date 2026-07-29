import SwiftUI
import CoreData

struct HomeInventoryView: View {
    private let household: Household

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<GroceryItem>

    @State private var editorMode: ItemEditorView.Mode?
    @State private var showingHousehold = false

    init(household: Household) {
        self.household = household
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "locationRawValue == %@ AND household == %@",
            ItemLocation.atHome.rawValue, household
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _items = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        List {
            ForEach(CategorySection.sections(from: items)) { section in
                Section(section.category.displayName) {
                    ForEach(section.items, id: \.objectID) { item in
                        ItemRowView(item: item,
                                    onAdjust: { delta in
                                        // Persists immediately; reaching zero removes the item.
                                        GroceryStore.adjustQuantity(item, by: delta, context: context)
                                    })
                            .contentShape(Rectangle())
                            .onTapGesture { editorMode = .edit(item) }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(item)
                                    try? context.save()
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Move to Shopping List", systemImage: "cart") {
                                    GroceryStore.moveBackToShoppingList(item, context: context)
                                }
                                .tint(.blue)
                            }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                EmptyStateView(systemImage: "house",
                               title: "Nothing at home yet",
                               message: "Items you check off on the shopping list land here. You can also add what you already own.",
                               actionTitle: "Add Item",
                               action: { editorMode = .add(.atHome) })
            }
        }
        .navigationTitle("At Home")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Household", systemImage: "person.2") { showingHousehold = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") { editorMode = .add(.atHome) }
            }
        }
        .sheet(item: $editorMode) { mode in
            ItemEditorView(mode: mode, household: household)
        }
        .sheet(isPresented: $showingHousehold) {
            HouseholdView(household: household)
        }
    }
}
