import SwiftUI
import CoreData

struct ShoppingListView: View {
    private let household: Household

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<GroceryItem>

    @State private var editorMode: ItemEditorView.Mode?
    @State private var showingHousehold = false
    @State private var banner: UndoBanner?
    @State private var bannerDismissTask: Task<Void, Never>?

    /// View-local by design: leaving the tab dismisses the banner, and "Move to
    /// Shopping List" on the At Home screen is the permanent recovery path.
    private struct UndoBanner {
        var message: String
        var undo: CheckOffUndo?
    }

    init(household: Household) {
        self.household = household
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "locationRawValue == %@ AND household == %@",
            ItemLocation.shoppingList.rawValue, household
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
                                    onCheckOff: { checkOff(item) },
                                    onAdjust: { delta in
                                        GroceryStore.adjustQuantity(item, by: delta, context: context)
                                    })
                            .contentShape(Rectangle())
                            .onTapGesture { editorMode = .edit(item) }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    // Deleting from the list never touches the inventory.
                                    context.delete(item)
                                    try? context.save()
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                EmptyStateView(systemImage: "cart",
                               title: "Nothing to buy",
                               message: "Add your first item and it will be sorted into a category automatically.",
                               actionTitle: "Add Item",
                               action: { editorMode = .add(.shoppingList) })
            }
        }
        .overlay(alignment: .bottom) {
            if let banner {
                UndoBannerView(message: banner.message,
                               onUndo: banner.undo.map { undo in { performUndo(undo) } },
                               onDismiss: dismissBanner)
            }
        }
        .navigationTitle("Shopping List")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Household", systemImage: "person.2") { showingHousehold = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") { editorMode = .add(.shoppingList) }
            }
        }
        .sheet(item: $editorMode) { mode in
            ItemEditorView(mode: mode, household: household)
        }
        .sheet(isPresented: $showingHousehold) {
            HouseholdView(household: household)
        }
        .onDisappear { dismissBanner() }
    }

    /// Single tap, no confirmation dialog — the undo banner is the safety net.
    private func checkOff(_ item: GroceryItem) {
        let name = item.displayName
        guard let undo = GroceryStore.checkOff(item, context: context) else { return }
        showBanner(UndoBanner(message: "Checked off \(name)", undo: undo))
    }

    private func performUndo(_ undo: CheckOffUndo) {
        switch GroceryStore.undoCheckOff(undo, context: context) {
        case .reversed:
            dismissBanner()
        case .changedElsewhere:
            showBanner(UndoBanner(message: "\(undo.name) was changed elsewhere and left as-is",
                                  undo: nil))
        }
    }

    private func showBanner(_ newBanner: UndoBanner) {
        banner = newBanner
        bannerDismissTask?.cancel()
        bannerDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            banner = nil
        }
    }

    private func dismissBanner() {
        bannerDismissTask?.cancel()
        banner = nil
    }
}

struct UndoBannerView: View {
    let message: String
    var onUndo: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer()
            if let onUndo {
                Button("Undo", action: onUndo)
                    .fontWeight(.semibold)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
