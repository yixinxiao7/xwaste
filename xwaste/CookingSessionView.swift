import SwiftUI
import CoreData

/// Session state is view-local `@State`, presented as a `.sheet` on every
/// platform (`fullScreenCover` is iOS-only): "clean slate every time" and
/// "nothing persists across relaunch" fall out of the presentation for free
/// rather than needing a persisted entity.
struct CookingSessionView: View {
    @ObservedObject var recipe: Recipe
    var onFinish: (CookUndo) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var checkedIngredients: Set<NSManagedObjectID> = []
    @State private var checkedSteps: Set<NSManagedObjectID> = []

    private var hasProgress: Bool {
        !checkedIngredients.isEmpty || !checkedSteps.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Ingredients") {
                    ForEach(recipe.orderedIngredients, id: \.objectID) { ingredient in
                        toggleRow(title: "\(ingredient.displayName) ×\(ingredient.quantity)",
                                 isChecked: checkedIngredients.contains(ingredient.objectID)) {
                            toggleIngredient(ingredient.objectID)
                        }
                    }
                }
                Section("Steps") {
                    ForEach(recipe.orderedSteps, id: \.objectID) { step in
                        toggleRow(title: step.displayText,
                                 isChecked: checkedSteps.contains(step.objectID)) {
                            toggleStep(step.objectID)
                        }
                    }
                }
            }
            .navigationTitle(recipe.displayName)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish Cooking") { finish() }
                }
            }
            // Turns on once anything is checked, so a swipe-down cannot end a
            // session in progress; before that, swipe-down is just cancel.
            .interactiveDismissDisabled(hasProgress)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func toggleRow(title: String, isChecked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? .green : .secondary)
                Text(title)
                    .strikethrough(isChecked)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isChecked ? "Checked" : "Unchecked")
    }

    private func toggleIngredient(_ id: NSManagedObjectID) {
        if checkedIngredients.contains(id) { checkedIngredients.remove(id) } else { checkedIngredients.insert(id) }
    }

    private func toggleStep(_ id: NSManagedObjectID) {
        if checkedSteps.contains(id) { checkedSteps.remove(id) } else { checkedSteps.insert(id) }
    }

    /// Always enabled — the recipe was only reachable here because Start
    /// Cooking was already enabled, i.e. the recipe was cookable.
    private func finish() {
        guard let undo = RecipeStore.consume(recipe, context: context) else {
            dismiss()
            return
        }
        dismiss()
        onFinish(undo)
    }
}
