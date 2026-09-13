import SwiftUI
import CoreData

/// One tile in the Recipes grid: photo or placeholder, name, and a status
/// icon. Identifiers on the leaf elements only — a container-level identifier
/// overwrites every descendant's (bug-039).
struct RecipeTileView: View {
    @ObservedObject var recipe: Recipe
    let canMake: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .aspectRatio(4 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                statusIcon
                    .padding(6)
            }
            Text(recipe.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .accessibilityIdentifier("recipeTileName")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = recipe.imageData,
           let cgImage = RecipeImage.cachedDecode(data: data, cacheKey: recipe.objectID.uriRepresentation().absoluteString) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .accessibilityIdentifier("recipeTileImage")
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("recipeTilePlaceholder")
        }
    }

    private var statusIcon: some View {
        Image(systemName: canMake ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(.white, canMake ? .green : .red)
            .font(.title3)
            .background(Circle().fill(.white).padding(2))
            .accessibilityLabel(canMake ? "Can make" : "Missing ingredients")
            .accessibilityIdentifier("recipeTileStatus")
    }
}
