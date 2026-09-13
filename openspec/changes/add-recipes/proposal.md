## Why

The app already answers "do I have this?" at the moment of adding. It cannot yet answer the question that follows: "what can I cook with what I have?" Recipes kept against the household's live At Home inventory turn that inventory from a list into an answer — which dishes are cookable right now, which ingredient stands in the way, and one tap to put exactly the shortfall on the shopping list. Finishing a cook then draws the ingredients back down, so the inventory stays true without hand edits. It is the same waste-reduction loop, closed from the kitchen end.

## What Changes

- A third tab, **Recipes**, beside Shopping List and At Home. Its toolbar has a plus button; its body is a lazily rendered grid of recipe tiles — photo (or a default placeholder), name, and a status icon: a check when At Home covers every ingredient, an x otherwise. Ordered by name.
- **Create, edit, and delete recipes.** The editor takes a name, an optional photo from the photo library, a short description, ingredients as name + whole-number count for one serving, and ordered steps. Save or cancel. Delete gets an undo banner. While typing an ingredient name the editor shows how many are at home, so ingredients get spelled the way the inventory spells them.
- **Availability status** computed locally against the household's At Home inventory with the existing normalized-name match. The recipe page shows the same icon beside the name and marks each ingredient that falls short with an x.
- **Filter** on the Recipes page — All / Can Make / Missing. The stretch goal is in scope: status is one in-memory pass over ingredient counts against a dictionary of the inventory, so the filter costs nothing measurable at household scale (hundreds of recipes, not millions).
- **Add Missing to Shopping List** on a recipe with shortfalls: raises each short ingredient's list quantity to at least its shortfall, merging into existing list rows, so tapping it twice buys nothing extra.
- **Cooking session.** A "Start Cooking" button on the recipe page — enabled only when the recipe can be made (user decision) — opens a session with a toggleable ingredient checklist for preparation and a toggleable step checklist for cooking. Every session starts unchecked. Cancel discards it. **Finish Cooking** subtracts the ingredients from At Home, with an undo banner that verifies before reversing, like check-off undo.
- Recipes belong to the **household**: they sync across the user's devices and reach household members through the existing share, exactly like items.
- Core Data model version 2 with three new entities; the matching CloudKit record types are pushed to the development schema and deployed to production before the next TestFlight build.
- Nothing on the watch. The Mac gets the tab through the shared target, with the usual Mac idioms (context menus, ⌘N, Escape).

## Capabilities

### New Capabilities

- `recipes`: The recipe record and its editor, the Recipes tab and tile grid, availability status and per-ingredient shortfalls against At Home, the All / Can Make / Missing filter, edit and delete with undo, Add Missing to Shopping List, image handling, and household ownership and sync.
- `cooking-session`: The Start Cooking rule, the session page with its two fresh checklists, cancel, and Finish Cooking consuming inventory with a verifying undo.

### Modified Capabilities

- `mac-experience`: The feature-parity requirement gains recipes and cooking sessions, with Mac input paths for tile actions and the session.
- `watch-app`: The scope requirement explicitly excludes recipes and cooking sessions from the watch.

## Impact

- **Data model**: a new `XWaste 2` model version (lightweight, additive migration) adding `Recipe`, `RecipeIngredient`, `RecipeStep`, and a `Household.recipes` inverse. Every attribute optional or defaulted, every relationship inversed, no ordered relationships — the CloudKit constraints — with explicit order indexes on ingredients and steps. Image bytes stored as external binary data so CloudKit carries them as assets.
- **CloudKit**: three new record types. Development schema push through the existing `PUSH_CK_SCHEMA=1` path, then a manual deploy to production in CloudKit Console. This gates the TestFlight upload: production is append-only, and a build whose record types are missing there cannot sync recipes (local use is unaffected).
- **Code**: new files in `xwaste/` — the three model classes, `RecipeStore` (create/update/delete with snapshot undo, consume with verifying undo, add-missing top-up), `RecipeAvailability` (pure status logic), `RecipeImage` (ImageIO downscale and decode, no UIKit/AppKit), `RecipesView`, `RecipeTileView`, `RecipeDetailView`, `RecipeEditorView`, `CookingSessionView`. `RootTabView` gains the tab. `LaunchSupport`'s seed gains two recipes. `GroceryStore` is reused unmodified for every shopping-list and inventory write. `UndoBannerView` is reused for the two new banners.
- **Xcode project**: the watch target's membership exception set must list every new UI file, or they silently join the watch build and break it. The model and logic files deliberately join the watch target so its Core Data stack knows the new entities. No new targets.
- **Frameworks**: `PhotosUI` for the picker (out-of-process, no photo-library permission string needed) and `ImageIO` for downscaling.
- **Tests**: unit tests for availability, ingredient merging, consume and its undo, delete and its undo, add-missing, and the image size bound; iOS UI tests over seeded recipes for the tab, filter, detail marks, session, finish and undo, create and delete. The Mac is driven directly. A hardware pass on TestFlight covers recipe sync, sharing, and migration over existing data.
- **Docs**: README feature list, CLAUDE.md current-state note, OpenWolf anatomy and cerebrum.
