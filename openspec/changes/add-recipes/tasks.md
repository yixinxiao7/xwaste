> Order matters in two places. The model version (group 1) comes first because everything else compiles against it, and the CloudKit production deploy (7.1) must precede the TestFlight upload (7.2) — production is append-only and a build shipped without its record types cannot sync recipes. Every new view file must be added to the watch target's exception set (4.9) or the watch build breaks silently.
> Verification is automation-first, as in `add-watchos-macos`: groups 3 and 5 involve no human; group 6 is agent-driven on the Mac; group 7 is the only hardware pass and needs the user's iPhone.

## 1. Data model and CloudKit development schema

- [x] 1.1 Add a second model version `XWaste 2.xcdatamodel` inside `XWaste.xcdatamodeld` (copy of v1 plus the new entities) and a `.xccurrentversion` pointing at it. Leave v1 untouched so lightweight migration can find the source model.
- [x] 1.2 In v2 add `Recipe` (name String, summary String, imageData Binary with external storage, createdAt Date, `household` to-one, `ingredients` and `steps` to-many cascade), `RecipeIngredient` (name, normalizedName, quantity Int64 default 1, orderIndex Int64 default 0, `recipe` to-one), `RecipeStep` (text, orderIndex Int64 default 0, `recipe` to-one), and `Household.recipes` (to-many, cascade). Every attribute optional or defaulted, every relationship inversed, nothing ordered, no unique constraints, `codeGenerationType` omitted.
- [x] 1.3 Write `Recipe.swift`, `RecipeIngredient.swift`, `RecipeStep.swift` as `nonisolated` `NSManagedObject` subclasses with `fetchRequest()` helpers, `displayName`, and `orderedIngredients`/`orderedSteps` sorted by `orderIndex`; add `recipes` and `recipesArray` to `Household`.
- [x] 1.4 Build iOS, watchOS, and macOS destinations. Confirm the watch target picked up the model files without an exception entry and still builds.
- [x] 1.5 Confirm lightweight migration: install the current `main` build on a simulator, add items, install the new build over it, confirm items and household survive and `Recipe` fetches return empty rather than throwing.
- [x] 1.6 User step: run once from the iPhone with `PUSH_CK_SCHEMA=1` to push the three record types to the CloudKit development schema; confirm `CD_Recipe`, `CD_RecipeIngredient`, `CD_RecipeStep` in CloudKit Console.

## 2. Pure logic and the store

- [x] 2.1 `RecipeAvailability.swift` (`nonisolated`): `inventory(from:)` building `[normalizedName: quantity]` from At Home items, and `evaluate(recipe:inventory:)` returning per-ingredient `shortfall` and `canMake` (zero ingredients → can make).
- [x] 2.2 `RecipeImage.swift` (`nonisolated`, ImageIO only): `downscaled(_ data: Data, maxPixelSize: 1024) -> Data?` producing an orientation-corrected JPEG, `decode(_ data: Data) -> CGImage?`, and a small `NSCache` keyed by object-ID URI plus byte count.
- [x] 2.3 `RecipeStore.swift`: `create` and `update` taking name, summary, image bytes, ingredient drafts, and step drafts — trim, drop blank rows, merge ingredient rows by `GroceryItem.normalize` (sum counts, keep first name and position), assign `orderIndex`, replace children wholesale on update.
- [x] 2.4 `RecipeStore.delete` returning a `RecipeSnapshot` (name, summary, image bytes, ingredient tuples, steps, household ID) and `undoDelete` recreating the graph in order.
- [x] 2.5 `RecipeStore.consume` returning `CookUndo` (recipe name, household ID, one line per ingredient with name, normalized name, category, manual flag, delta, and outcome `reduced(expected:)` or `removed`); absent rows are skipped, zero deletes the row.
- [x] 2.6 `RecipeStore.undoConsume` with per-line verification: expected quantity present → add the delta back; expected absent and absent → recreate with recorded name, category, manual flag; anything else → leave alone and return it in `.partiallyReversed(changedElsewhere:)`. Never treat a missing row as quantity 0.
- [x] 2.7 `RecipeStore.addMissingToShoppingList`: for each short ingredient raise the list row to `max(current, shortfall)` through `GroceryStore.findItem` and `addItem`; return what was added for the confirmation banner. No duplicate warning path.

## 3. Unit tests (`xwasteTests`, Swift Testing, in-memory stack)

- [x] 3.1 Availability: every ingredient covered; a count short; an ingredient absent; zero ingredients; "onions" matches "Onion"; shopping-list rows are ignored.
- [x] 3.2 Create merges duplicate ingredient rows (count 3, first name and position kept), drops blank ingredient and step rows, preserves order, rejects a blank name.
- [x] 3.3 Update replaces ingredients and steps wholesale and keeps the recipe's identity and image when unchanged; removing the image clears `imageData`.
- [x] 3.4 Delete returns a complete snapshot; `undoDelete` restores name, summary, image bytes, ingredients in order, and steps in order under the same household.
- [x] 3.5 Consume reduces matching rows, deletes at zero, skips absent rows, leaves shopping-list rows alone, and records one line per ingredient with the right outcome.
- [x] 3.6 Undo consume: full reversal including recreating a removed row with its category and manual flag; a row changed elsewhere is left as set and reported; a removed row that was re-added is left at the new quantity and reported; an unused undo changes nothing.
- [x] 3.7 Add missing: creates rows with the shortfall and automatic category; second call changes nothing; partial list coverage is topped up; a covering row is untouched; a cookable recipe adds nothing.
- [x] 3.8 Image: a 3000×2000 input downscales to ≤1024 on the long side; a 400×300 input is not upscaled; garbage bytes return nil; a rotated-by-EXIF input comes out with the visual orientation applied.
- [x] 3.9 `xcodebuild test` on the iOS simulator is green for the whole `xwasteTests` target, including the existing suites.

## 4. UI

- [x] 4.1 `RootTabView`: third `NavigationStack { RecipesView(household:) }` with `Label("Recipes", systemImage: "book")`; Shopping List stays first. Mac `defaultSize`/`minWidth` unchanged (three tabs fit at 480 pt — confirm).
- [x] 4.2 `RecipeTileView`: image or symbol placeholder in a fixed-aspect rounded rect, name below, status icon (`checkmark.circle.fill` green / `xmark.circle.fill` red) with accessibility labels "Can make" / "Missing ingredients", identifiers on leaves only.
- [x] 4.3 `RecipesView`: `@FetchRequest` of recipes sorted by name (localized, case-insensitive) scoped to the household; `@FetchRequest` of At Home items feeding `RecipeAvailability.inventory`; segmented filter (All / Can Make / Missing, `@State`, default All) in a top `safeAreaInset`; `ScrollView` + adaptive `LazyVGrid`; tile tap pushes the detail via `navigationDestination`; tile `.contextMenu` with Edit and Delete; toolbar Household button (as on the other tabs) and a plus button with `.keyboardShortcut("n")`; empty state for no recipes and a distinct one for a filter with no matches; delete undo banner using `UndoBannerView` and `LaunchSupport.confirmationDuration`, dismissed on disappear.
- [x] 4.4 `RecipeEditorView` (sheet, `Mode.add`/`.edit` like `ItemEditorView`): name field focused on add; `PhotosPicker` "Choose Photo" with thumbnail and "Remove Photo", downscaling through `RecipeImage` on selection; description `TextField(axis: .vertical)`; ingredient rows (name field, `Stepper` 1…999, per-row remove button) with "Add Ingredient" and the inline "You have N at home" note under a matching name; step rows (`TextField(axis: .vertical)`, per-row remove) with "Add Step"; Cancel / Save (`cancellationAction`/`confirmationAction`, Save disabled on blank name). `textInputAutocapitalization` guarded by `#if !os(macOS)`.
- [x] 4.5 `RecipeDetailView`: name with status icon, image or placeholder, description, ingredients with counts and an x on each shortfall (optionally "have N"), steps in order; own At Home `@FetchRequest` so status is live; toolbar Edit and Delete (delete pops back and shows the Recipes banner); "Add Missing to Shopping List" shown only when not cookable, with a plain confirmation banner naming what was added; "Start Cooking" button disabled when not cookable; cook undo banner on this view.
- [x] 4.6 `CookingSessionView`: `.sheet` on every platform, `NavigationStack` inside, ingredient checklist (name ×count) and step checklist as toggle rows backed by two `@State` index sets; Cancel as `cancellationAction`, Finish Cooking as `confirmationAction` (always enabled); `.interactiveDismissDisabled` once any entry is checked; macOS `minWidth`/`minHeight`. Finish calls `RecipeStore.consume`, dismisses, and hands the `CookUndo` to the detail view's banner.
- [x] 4.7 Wire the two undo banners: delete undo on `RecipesView` (`undoDelete`), cook undo on `RecipeDetailView` (`undoConsume`, with the "changed elsewhere and left as-is" message for the partial case), both auto-dismissing after `LaunchSupport.confirmationDuration`.
- [x] 4.8 Extend `LaunchSupport` seed `1` with "Buttered Toast" (Butter ×1; description; two steps) and "Onion Soup" (Onion ×3, Butter ×1; three steps), adding no items. Extend `PersistenceController.preview` the same way.
- [x] 4.9 Add every new view file (`RecipesView`, `RecipeTileView`, `RecipeDetailView`, `RecipeEditorView`, `CookingSessionView`) to the watch target's `PBXFileSystemSynchronizedBuildFileExceptionSet`; `plutil -lint` the pbxproj; build the watch target and the existing watch UI tests still pass.
- [x] 4.10 Compile-check macOS (`-destination 'platform=macOS'`) and visionOS; no iOS-only API slipped in.

## 5. iOS UI tests (`xwasteUITests`, seeded, `XWASTE_CONFIRMATION_SECONDS` widened)

- [x] 5.1 Recipes tab is reachable; both seeded tiles appear in name order with "Buttered Toast" marked can-make and "Onion Soup" marked missing; the placeholder shows for both.
- [x] 5.2 Filter: Can Make leaves only "Buttered Toast"; Missing leaves only "Onion Soup"; All restores both; a filter with no matches shows the filtered empty state.
- [x] 5.3 "Onion Soup" detail: x beside the name and beside "Onion" ×3, none beside "Butter" ×1; Start Cooking present and disabled; Add Missing present.
- [x] 5.4 Add Missing on "Onion Soup": the seeded shopping-list "Onion" ×2 row becomes ×3 (top-up), no new row; tapping again leaves ×3; no duplicate-warning alert appears.
- [x] 5.5 "Buttered Toast" session: Start Cooking opens the session with every entry unchecked; toggling an ingredient and a step checks them; Cancel returns to the recipe; starting again shows everything unchecked.
- [x] 5.6 Finish Cooking on "Buttered Toast": At Home no longer lists Butter; the undo banner names the recipe; Undo restores "Butter" ×1 under Dairy & Eggs; recipe status returns to can-make.
- [x] 5.7 Create flow: plus → editor → name, one ingredient, one step → Save → new tile appears in name order; Cancel from a fresh editor creates nothing.
- [x] 5.8 Delete with undo: context-menu Delete removes the tile and shows the banner; Undo restores the tile with its ingredients visible on the detail page.
- [x] 5.9 Existing `XWasteRegressionUITests` still pass with the extended seed.

## 6. Mac verification (agent-driven, seeded binary)

- [x] 6.1 Launch the Mac binary with `XWASTE_UITEST_SEED=1 XWASTE_CONFIRMATION_SECONDS=600`; Recipes tab, grid at two columns at the 480 pt floor, tiles and status icons render; window minimum still fits three tabs and the toolbar.
- [x] 6.2 Right-click a tile offers Edit and Delete; ⌘N opens the editor; the editor and session sheets are usable at minimum window size; `PhotosPicker` presents and returns an image (fallback to `.fileImporter` if it misbehaves, per design).
- [x] 6.3 Start Cooking, check entries with the mouse, Escape cancels with no inventory change; Finish Cooking reduces At Home and the banner's Undo restores it.

## 7. CloudKit production and hardware (user's iPhone; TestFlight)

- [ ] 7.1 Deploy the development schema changes to production in CloudKit Console; confirm the three record types exist in production. This gates 7.2.
- [ ] 7.2 Upload a TestFlight build; install over the phone's existing data; confirm items, household, and sharing state survive the migration and recipes can be created.
- [ ] 7.3 Same-account sync: create a recipe with a photo on the phone, confirm it appears on the Mac (same signing environment as the phone, per the dev/prod note) with image and status; edit on the Mac, confirm the phone updates.
- [ ] 7.4 Sharing: with the second account used for the v1 sharing verification, confirm a recipe created by one member appears for the other with status computed against the shared inventory, and that Finish Cooking on one device reduces the other's At Home.
- [ ] 7.5 Confirm the previous TestFlight build (if still installed on any device) keeps working against the zone once recipe records exist.

## 8. Docs and OpenWolf

- [x] 8.1 README: three-tab description and the recipes/cooking paragraph; CLAUDE.md current-state note (eight capabilities → ten, model version 2, production schema deployed).
- [x] 8.2 `.wolf/anatomy.md` entries for every new file; `.wolf/cerebrum.md` decision-log entries (household ownership, disabled Start Cooking as the scoped block exception, top-up semantics, model versioning) and any learnings from the picker or migration; `.wolf/memory.md` session log.
