import SwiftUI
import CoreData

/// Own At Home fetch so status stays live while this screen is open — the
/// same reason `RecipesView` holds one. `onDelete` hands the snapshot back to
/// the presenting `RecipesView` so its banner (not a screen about to pop) is
/// the one that shows Undo.
struct RecipeDetailView: View {
    @ObservedObject var recipe: Recipe
    let household: Household
    var onDelete: (RecipeSnapshot) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var homeItems: FetchedResults<GroceryItem>

    @State private var editorMode: RecipeEditorView.Mode?
    @State private var showingCookingSession = false
    @State private var cookBanner: CookBanner?
    @State private var cookBannerDismissTask: Task<Void, Never>?
    @State private var addedMissingMessage: String?
    @State private var addedMissingDismissTask: Task<Void, Never>?

    private struct CookBanner {
        var message: String
        var undo: CookUndo?
    }

    init(recipe: Recipe, household: Household, onDelete: @escaping (RecipeSnapshot) -> Void = { _ in }) {
        self.recipe = recipe
        self.household = household
        self.onDelete = onDelete
        let request = GroceryItem.fetchRequest()
        request.predicate = NSPredicate(
            format: "locationRawValue == %@ AND household == %@",
            ItemLocation.atHome.rawValue, household
        )
        // NSFetchedResultsController (which @FetchRequest wraps) requires at
        // least one sort descriptor or it throws at init.
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _homeItems = FetchRequest(fetchRequest: request, animation: .default)
    }

    private var status: RecipeStatus {
        RecipeAvailability.evaluate(recipe: recipe, inventory: RecipeAvailability.inventory(from: homeItems))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(recipe.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                    statusIcon
                }
                imageView
                if let summary = recipe.summary, !summary.isEmpty {
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
                if !status.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients").font(.headline)
                        ForEach(status.ingredients, id: \.ingredient.objectID) { entry in
                            HStack {
                                if entry.isShort {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .accessibilityLabel("Missing")
                                }
                                Text("\(entry.ingredient.displayName) ×\(entry.ingredient.quantity)")
                                Spacer()
                            }
                        }
                    }
                }
                if !recipe.orderedSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps").font(.headline)
                        ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.objectID) { index, step in
                            HStack(alignment: .top) {
                                Text("\(index + 1).").foregroundStyle(.secondary)
                                Text(step.displayText)
                            }
                        }
                    }
                }
                if !status.canMake {
                    Button("Add Missing to Shopping List") { addMissing() }
                        .buttonStyle(.bordered)
                }
                Button("Start Cooking") { showingCookingSession = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!status.canMake)
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let cookBanner {
                UndoBannerView(message: cookBanner.message,
                               onUndo: cookBanner.undo.map { undo in { performCookUndo(undo) } },
                               onDismiss: dismissCookBanner)
            } else if let addedMissingMessage {
                UndoBannerView(message: addedMissingMessage, onDismiss: dismissAddedMissingBanner)
            }
        }
        .navigationTitle(recipe.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", systemImage: "pencil") { editorMode = .edit(recipe) }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
            }
        }
        .sheet(item: $editorMode) { mode in
            RecipeEditorView(mode: mode, household: household)
        }
        .sheet(isPresented: $showingCookingSession) {
            CookingSessionView(recipe: recipe) { undo in
                cookBanner = CookBanner(message: "Cooked \(recipe.displayName)", undo: undo)
                scheduleCookBannerDismiss()
            }
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let data = recipe.imageData,
           let cgImage = RecipeImage.cachedDecode(data: data, cacheKey: recipe.objectID.uriRepresentation().absoluteString) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var statusIcon: some View {
        Image(systemName: status.canMake ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(status.canMake ? .green : .red)
            .accessibilityLabel(status.canMake ? "Can make" : "Missing ingredients")
    }

    private func delete() {
        guard let snapshot = RecipeStore.delete(recipe, context: context) else { return }
        onDelete(snapshot)
        dismiss()
    }

    private func addMissing() {
        let inventory = RecipeAvailability.inventory(from: homeItems)
        let added = RecipeStore.addMissingToShoppingList(recipe, inventory: inventory, context: context)
        guard !added.isEmpty else { return }
        addedMissingMessage = "Added \(added.joined(separator: ", ")) to the shopping list"
        scheduleAddedMissingDismiss()
    }

    private func performCookUndo(_ undo: CookUndo) {
        switch RecipeStore.undoConsume(undo, context: context) {
        case .reversed:
            dismissCookBanner()
        case .partiallyReversed(let changedElsewhere):
            cookBanner = CookBanner(
                message: "\(changedElsewhere.joined(separator: ", ")) changed elsewhere and left as-is",
                undo: nil)
        }
    }

    private func scheduleCookBannerDismiss() {
        cookBannerDismissTask?.cancel()
        cookBannerDismissTask = Task {
            try? await Task.sleep(for: LaunchSupport.confirmationDuration)
            guard !Task.isCancelled else { return }
            cookBanner = nil
        }
    }

    private func dismissCookBanner() {
        cookBannerDismissTask?.cancel()
        cookBanner = nil
    }

    private func scheduleAddedMissingDismiss() {
        addedMissingDismissTask?.cancel()
        addedMissingDismissTask = Task {
            try? await Task.sleep(for: LaunchSupport.confirmationDuration)
            guard !Task.isCancelled else { return }
            addedMissingMessage = nil
        }
    }

    private func dismissAddedMissingBanner() {
        addedMissingDismissTask?.cancel()
        addedMissingMessage = nil
    }
}
