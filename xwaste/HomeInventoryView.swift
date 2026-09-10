import SwiftUI
import CoreData

struct HomeInventoryView: View {
    private let household: Household

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<GroceryItem>

    @State private var editorMode: ItemEditorView.Mode?
    @State private var showingHousehold = false
    /// Only the Mac needs a selected row — it is what the delete key acts on.
    @State private var selection: NSManagedObjectID?

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
        List(selection: $selection) {
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
                                    delete(item)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Move to Shopping List", systemImage: "cart") {
                                    moveBack(item)
                                }
                                .tint(.blue)
                            }
                            // The Mac's only route to these actions; on iOS a
                            // deliberate duplicate of the swipe actions.
                            .contextMenu {
                                Button("Move to Shopping List", systemImage: "cart") { moveBack(item) }
                                Button("Edit", systemImage: "pencil") { editorMode = .edit(item) }
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                            }
                    }
                }
            }
        }
        #if os(macOS)
        .onDeleteCommand(perform: deleteSelection)
        .id(structureID)
        #endif
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
                    // ⌘N on the Mac; harmless on iOS with a hardware keyboard.
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editorMode) { mode in
            ItemEditorView(mode: mode, household: household)
        }
        .sheet(isPresented: $showingHousehold) {
            HouseholdView(household: household)
        }
    }

    /// Identity of the list's *structure* — every row, in order. SwiftUI's
    /// AppKit list mis-diffs a row removal out of a multi-section `List`: the
    /// surviving rows keep the right count but redraw with a neighbour's
    /// content, so a section header appears in a row slot. Rebuilding the list
    /// whenever the set of rows changes sidesteps the bad diff. macOS only —
    /// iOS diffs correctly and keeps its animations.
    private var structureID: String {
        items.map { $0.objectID.uriRepresentation().absoluteString }.joined(separator: "|")
    }

    /// A selection that outlives its row leaves the macOS list diffing against
    /// a row that no longer exists, and it renders the *neighbouring* rows with
    /// the wrong content — a section header can end up drawn in a row slot.
    /// Every path that removes a row has to drop the selection first.
    private func forgetSelection(of item: GroceryItem) {
        if selection == item.objectID { selection = nil }
    }

    private func delete(_ item: GroceryItem) {
        forgetSelection(of: item)
        context.delete(item)
        try? context.save()
    }

    private func moveBack(_ item: GroceryItem) {
        forgetSelection(of: item)
        GroceryStore.moveBackToShoppingList(item, context: context)
    }

    /// The delete key's target on the Mac, where there is no swipe gesture.
    private func deleteSelection() {
        guard let selection,
              let item = try? context.existingObject(with: selection) as? GroceryItem else { return }
        delete(item)
    }
}
