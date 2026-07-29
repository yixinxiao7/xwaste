import SwiftUI
import CoreData

/// One sheet for both add and edit, on both screens. Carries the duplicate
/// warning: a live inline on-hand note while typing, and a confirmation alert
/// on save. The warning informs, never blocks — "Add Anyway" completes the add
/// exactly as if no warning had appeared.
struct ItemEditorView: View {
    enum Mode {
        case add(ItemLocation)
        case edit(GroceryItem)
    }

    let mode: Mode
    let household: Household

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var quantity: Int64
    /// nil means Automatic.
    @State private var manualCategory: GroceryCategory?
    @State private var showAlreadyAtHomeAlert = false
    @State private var alertOnHandCount: Int64 = 0
    @FocusState private var nameFieldFocused: Bool

    init(mode: Mode, household: Household) {
        self.mode = mode
        self.household = household
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _quantity = State(initialValue: 1)
            _manualCategory = State(initialValue: nil)
        case .edit(let item):
            _name = State(initialValue: item.displayName)
            _quantity = State(initialValue: item.quantity)
            _manualCategory = State(initialValue: item.categoryIsManual ? item.category : nil)
        }
    }

    private var location: ItemLocation {
        switch mode {
        case .add(let location): location
        case .edit(let item): item.location
        }
    }

    /// The warning exists to surface at-home stock when shopping; it never
    /// applies to items added or edited directly in the inventory.
    private var warningApplies: Bool { location == .shoppingList }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// On-hand quantity for the currently typed name, evaluated against local
    /// storage only — never waits on the network.
    private var onHandQuantity: Int64? {
        let normalized = GroceryItem.normalize(name)
        guard !normalized.isEmpty,
              let match = GroceryStore.findItem(normalizedName: normalized, location: .atHome,
                                                household: household, in: context),
              match.quantity >= 1 else { return nil }
        // An at-home item being edited is not a duplicate of itself.
        if case .edit(let editing) = mode, editing == match { return nil }
        return match.quantity
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFieldFocused)
                    #if !os(macOS)
                        .textInputAutocapitalization(.words)
                    #endif
                    if warningApplies, let count = onHandQuantity {
                        Label("You have \(count) at home", systemImage: "house")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }
                Section {
                    Picker("Category", selection: $manualCategory) {
                        Text("Automatic").tag(GroceryCategory?.none)
                        ForEach(GroceryCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.sfSymbol)
                                .tag(GroceryCategory?.some(category))
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if case .add = mode { nameFieldFocused = true }
            }
            .alert("Already at home", isPresented: $showAlreadyAtHomeAlert) {
                Button("Add Anyway") { commit() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You already have \(alertOnHandCount) \(trimmedName) at home.")
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: "Add Item"
        case .edit: "Edit Item"
        }
    }

    private func attemptSave() {
        // Blank names are rejected without dismissing; the field stays active.
        guard !trimmedName.isEmpty else {
            nameFieldFocused = true
            return
        }
        if warningApplies, shouldWarn, let count = onHandQuantity {
            alertOnHandCount = count
            showAlreadyAtHomeAlert = true
            return
        }
        commit()
    }

    private var shouldWarn: Bool {
        switch mode {
        case .add:
            // Fires on the merge path too: an existing list row does not tell
            // the user what is sitting at home. Only at-home stock gates it.
            return onHandQuantity != nil
        case .edit(let item):
            // A rename that makes the item match at-home stock warns; an edit
            // that keeps the name does not re-warn.
            return GroceryItem.normalize(name) != item.normalizedName && onHandQuantity != nil
        }
    }

    private func commit() {
        switch mode {
        case .add(let location):
            let normalized = GroceryItem.normalize(trimmedName)
            let mergeTarget = GroceryStore.findItem(normalizedName: normalized, location: location,
                                                    household: household, in: context)
            let item = GroceryStore.addItem(name: trimmedName, quantity: quantity,
                                            location: location, household: household, context: context)
            // A merged-into row keeps its own category and manual flag.
            if mergeTarget == nil, let manualCategory {
                GroceryStore.setCategory(item, to: manualCategory, context: context)
            }
        case .edit(let item):
            let wasManual = item.categoryIsManual
            GroceryStore.setQuantity(item, to: quantity, context: context)
            let surviving = GroceryStore.rename(item, to: trimmedName, context: context)
            // On a rename-merge the surviving row keeps its own category and
            // manual flag; the editor's category choice applies only otherwise.
            if surviving == item {
                if let manualCategory {
                    GroceryStore.setCategory(surviving, to: manualCategory, context: context)
                } else if wasManual {
                    GroceryStore.revertToAutomaticCategory(surviving, context: context)
                }
            }
        }
        dismiss()
    }
}

extension ItemEditorView.Mode: Identifiable {
    var id: String {
        switch self {
        case .add(let location): "add-\(location.rawValue)"
        case .edit(let item): item.objectID.uriRepresentation().absoluteString
        }
    }
}
