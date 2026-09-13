import SwiftUI
import CoreData
import PhotosUI

/// One sheet for both add and edit, mirroring `ItemEditorView`'s shape.
/// Ingredient rows show the same live "you have N at home" note the item
/// editor shows, so ingredients get spelled the way the inventory spells them.
struct RecipeEditorView: View {
    enum Mode: Identifiable {
        case add
        case edit(Recipe)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let recipe): recipe.objectID.uriRepresentation().absoluteString
            }
        }
    }

    private struct IngredientRow: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Int64
    }

    private struct StepRow: Identifiable {
        let id = UUID()
        var text: String
    }

    let mode: Mode
    let household: Household

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var summary: String
    @State private var imageData: Data?
    @State private var ingredientRows: [IngredientRow]
    @State private var stepRows: [StepRow]
    @State private var photoPickerItem: PhotosPickerItem?
    @FocusState private var nameFieldFocused: Bool

    init(mode: Mode, household: Household) {
        self.mode = mode
        self.household = household
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _summary = State(initialValue: "")
            _imageData = State(initialValue: nil)
            _ingredientRows = State(initialValue: [])
            _stepRows = State(initialValue: [])
        case .edit(let recipe):
            _name = State(initialValue: recipe.displayName)
            _summary = State(initialValue: recipe.summary ?? "")
            _imageData = State(initialValue: recipe.imageData)
            _ingredientRows = State(initialValue: recipe.orderedIngredients.map {
                IngredientRow(name: $0.displayName, quantity: $0.quantity)
            })
            _stepRows = State(initialValue: recipe.orderedSteps.map { StepRow(text: $0.displayText) })
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func onHandCount(for ingredientName: String) -> Int64? {
        let normalized = GroceryItem.normalize(ingredientName)
        guard !normalized.isEmpty,
              let match = GroceryStore.findItem(normalizedName: normalized, location: .atHome,
                                                household: household, in: context),
              match.quantity >= 1 else { return nil }
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
                    TextField("Description", text: $summary, axis: .vertical)
                }

                Section {
                    photoPicker
                }

                Section("Ingredients") {
                    ForEach($ingredientRows) { $row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Ingredient", text: $row.name)
                                if let count = onHandCount(for: row.name) {
                                    Text("You have \(count) at home")
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Stepper("Quantity: \(row.quantity)", value: $row.quantity, in: 1...999)
                                .labelsHidden()
                                .fixedSize()
                            Button(role: .destructive) {
                                ingredientRows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Ingredient", systemImage: "plus") {
                        ingredientRows.append(IngredientRow(name: "", quantity: 1))
                    }
                }

                Section("Steps") {
                    ForEach($stepRows) { $row in
                        HStack(alignment: .top) {
                            TextField("Step", text: $row.text, axis: .vertical)
                            Button(role: .destructive) {
                                stepRows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Step", systemImage: "plus") {
                        stepRows.append(StepRow(text: ""))
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
                    Button("Save") { commit() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                if case .add = mode { nameFieldFocused = true }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        imageData = RecipeImage.downscaled(data) ?? data
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var photoPicker: some View {
        HStack {
            if let imageData, let cgImage = RecipeImage.decode(imageData) {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Text("Choose Photo")
            }
            Spacer()
            if imageData != nil {
                Button("Remove Photo", role: .destructive) {
                    imageData = nil
                    photoPickerItem = nil
                }
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: "Add Recipe"
        case .edit: "Edit Recipe"
        }
    }

    private func commit() {
        guard !trimmedName.isEmpty else {
            nameFieldFocused = true
            return
        }
        let ingredientDrafts = ingredientRows.map { RecipeIngredientDraft(name: $0.name, quantity: $0.quantity) }
        let stepDrafts = stepRows.map { RecipeStepDraft(text: $0.text) }

        switch mode {
        case .add:
            RecipeStore.create(name: trimmedName, summary: summary, imageData: imageData,
                               ingredients: ingredientDrafts, steps: stepDrafts,
                               household: household, context: context)
        case .edit(let recipe):
            RecipeStore.update(recipe, name: trimmedName, summary: summary, imageData: imageData,
                               ingredients: ingredientDrafts, steps: stepDrafts, context: context)
        }
        dismiss()
    }
}
