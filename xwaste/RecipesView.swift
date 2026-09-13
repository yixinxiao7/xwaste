import SwiftUI
import CoreData

enum RecipeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case canMake = "Can Make"
    case missing = "Missing"

    var id: String { rawValue }
}

struct RecipesView: View {
    private let household: Household

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var recipes: FetchedResults<Recipe>
    @FetchRequest private var homeItems: FetchedResults<GroceryItem>

    @State private var filter: RecipeFilter = .all
    @State private var editorMode: RecipeEditorView.Mode?
    @State private var showingHousehold = false
    @State private var banner: UndoBanner?
    @State private var bannerDismissTask: Task<Void, Never>?

    /// View-local, like the shopping list's: leaving the tab dismisses it.
    private struct UndoBanner {
        var message: String
        var undo: RecipeSnapshot?
    }

    init(household: Household) {
        self.household = household

        let recipeRequest = Recipe.fetchRequest()
        recipeRequest.predicate = NSPredicate(format: "household == %@", household)
        recipeRequest.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true,
                             selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]
        _recipes = FetchRequest(fetchRequest: recipeRequest, animation: .default)

        let homeRequest = GroceryItem.fetchRequest()
        homeRequest.predicate = NSPredicate(
            format: "locationRawValue == %@ AND household == %@",
            ItemLocation.atHome.rawValue, household
        )
        // NSFetchedResultsController (which @FetchRequest wraps) requires at
        // least one sort descriptor or it throws at init — this fetch's
        // result order is never displayed, but the requirement still applies.
        homeRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        _homeItems = FetchRequest(fetchRequest: homeRequest, animation: .default)
    }

    private var inventory: [String: Int64] {
        RecipeAvailability.inventory(from: homeItems)
    }

    private func canMake(_ recipe: Recipe) -> Bool {
        RecipeAvailability.evaluate(recipe: recipe, inventory: inventory).canMake
    }

    private var filteredRecipes: [Recipe] {
        switch filter {
        case .all: Array(recipes)
        case .canMake: recipes.filter(canMake)
        case .missing: recipes.filter { !canMake($0) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredRecipes, id: \.objectID) { recipe in
                    NavigationLink(value: recipe.objectID) {
                        RecipeTileView(recipe: recipe, canMake: canMake(recipe))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(recipe) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(recipe) }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Picker("Filter", selection: $filter) {
                ForEach(RecipeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .overlay {
            if recipes.isEmpty {
                EmptyStateView(systemImage: "book",
                               title: "No recipes yet",
                               message: "Add a recipe to see whether you can make it with what's at home.",
                               actionTitle: "Add Recipe",
                               action: { editorMode = .add })
            } else if filteredRecipes.isEmpty {
                EmptyStateView(systemImage: "line.3.horizontal.decrease.circle",
                               title: "No matching recipes",
                               message: "Try a different filter.")
            }
        }
        .overlay(alignment: .bottom) {
            if let banner {
                UndoBannerView(message: banner.message,
                               onUndo: banner.undo.map { snapshot in { performUndo(snapshot) } },
                               onDismiss: dismissBanner)
            }
        }
        .navigationTitle("Recipes")
        .navigationDestination(for: NSManagedObjectID.self) { id in
            if let recipe = try? context.existingObject(with: id) as? Recipe {
                RecipeDetailView(recipe: recipe, household: household) { snapshot in
                    showBanner(UndoBanner(message: "Deleted \(snapshot.name)", undo: snapshot))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Household", systemImage: "person.2") { showingHousehold = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Recipe", systemImage: "plus") { editorMode = .add }
                    // ⌘N on the Mac; harmless on iOS with a hardware keyboard.
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editorMode) { mode in
            RecipeEditorView(mode: mode, household: household)
        }
        .sheet(isPresented: $showingHousehold) {
            HouseholdView(household: household)
        }
        .onDisappear { dismissBanner() }
    }

    private func delete(_ recipe: Recipe) {
        let name = recipe.displayName
        guard let snapshot = RecipeStore.delete(recipe, context: context) else { return }
        showBanner(UndoBanner(message: "Deleted \(name)", undo: snapshot))
    }

    private func performUndo(_ snapshot: RecipeSnapshot) {
        RecipeStore.undoDelete(snapshot, context: context)
        dismissBanner()
    }

    private func showBanner(_ newBanner: UndoBanner) {
        banner = newBanner
        bannerDismissTask?.cancel()
        bannerDismissTask = Task {
            try? await Task.sleep(for: LaunchSupport.confirmationDuration)
            guard !Task.isCancelled else { return }
            banner = nil
        }
    }

    private func dismissBanner() {
        bannerDismissTask?.cancel()
        banner = nil
    }
}
