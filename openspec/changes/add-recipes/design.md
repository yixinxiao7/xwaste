## Context

See proposal.md for motivation. What shapes the approach:

- **Two-tab app over one `GroceryItem` model.** `RootTabView` holds two `NavigationStack`s; every fetch scopes to `persistence.activeHousehold`. Quantities are whole numbers; the "one row per normalized name per location" invariant is enforced in `GroceryStore`, and `GroceryItem.normalize` is the only matching rule in the app. Recipes must speak that same language or the status icon lies.
- **CloudKit model constraints** (every attribute optional or defaulted, every relationship inversed, no unique constraints) plus one more that matters here: **`NSPersistentCloudKitContainer` does not support ordered relationships**, so ingredient and step order has to be an explicit attribute.
- **Store placement is inferred from relationships.** No code calls `assign(_:to:)`; a new `GroceryItem` lands in the shared store because its `household` lives there. Recipes hung off `Household` inherit this for free, which is what makes household ownership a modelling choice rather than a sharing feature.
- **Editing the model in place breaks existing installs.** Lightweight migration needs the *source* model in the bundle to infer the mapping; TestFlight installs hold real data, so this change needs a proper second model version.
- **The production CloudKit schema is append-only and manually deployed.** New record types reach production only through CloudKit Console; a build shipped before that cannot sync recipes (local use still works).
- **Watch target membership is by exception list.** Any new UI file dropped into `xwaste/` silently joins the watch build and breaks it (`bug`-class learning in cerebrum). Non-UI files should join it: the watch opens the same store, so its model must know every entity.
- **iOS-only SwiftUI APIs are off limits** (`SUPPORTED_PLATFORMS` includes macOS and visionOS): `fullScreenCover`, `topBarLeading`, `navigationBarTitleDisplayMode`, camera pickers.
- **User decisions from the proposal Q&A (2026-09-13):** Finish Cooking consumes inventory with undo; recipes belong to the household; edit and delete with undo; whole counts for one serving, no servings multiplier; photo library only, no camera; Add Missing to Shopping List is in; **Start Cooking is disabled when ingredients are missing** — a deliberate, scoped exception to "warn, never block", chosen by the user.
- Existing verification stack: `xwasteTests` (Swift Testing over an in-memory stack), `xwasteUITests` driven through `LaunchSupport` env seams (`XWASTE_UITEST_SEED`, `XWASTE_CONFIRMATION_SECONDS`), no simulator GUI for the agent, Mac driven directly.

## Goals / Non-Goals

**Goals:**

- Status that is always right and always free: computed from the same normalized names the inventory uses, in memory, in one pass — never persisted, never stale, never a network call.
- Every recipe write goes through one place (`RecipeStore`) with the same shape as `GroceryStore`: value-snapshot undo, verify-before-reverse, no zero-quantity rows.
- Zero change to `GroceryStore` and the item invariants. Recipes are a consumer of the inventory, not a second inventory.
- One view body per screen, cross-platform, following the existing Mac-idiom pattern (context menus and shortcuts added everywhere, no forks).
- Migration and CloudKit schema handled as first-class tasks, not afterthoughts.

**Non-Goals:**

- Servings scaling, units of measure, nutrition, timers, recipe import (URL, photo OCR, clipboard), recipe search or tags.
- A camera path for images. Illustrated placeholder artwork (a symbol placeholder ships; artwork can replace it later without a spec change).
- Persisting cooking sessions or showing them on other devices.
- Suggesting "what to cook" beyond the can-make filter — no ranking, no partial-match ("missing one ingredient") tier.
- Anything on the watch. iPad-specific layout beyond what the adaptive grid gives.

## Decisions

### Three entities with explicit order indexes, in a new model version

`Recipe` (name, `summary`, `imageData`, `createdAt`, `household`, `ingredients`, `steps`), `RecipeIngredient` (name, `normalizedName`, `quantity` default 1, `orderIndex` default 0, `recipe`), `RecipeStep` (`text`, `orderIndex` default 0, `recipe`), and a `Household.recipes` inverse. Cascade from household to recipe and from recipe to its children; nullify upward. `imageData` is Binary with external storage on, which `NSPersistentCloudKitContainer` mirrors as a `CKAsset`. The description attribute is named `summary` because `description` collides with `NSObject`. Subclasses are hand-written and `nonisolated`, matching `GroceryItem`; `codeGenerationType` is omitted (writing `manual` breaks momc). `Recipe` gets `orderedIngredients`/`orderedSteps` accessors sorted by `orderIndex`.

The model becomes versioned: `XWaste 2.xcdatamodel` plus `.xccurrentversion`, v1 left untouched, so `NSPersistentContainer`'s default automatic lightweight migration can infer the additive mapping on every existing install (phone, Mac, watch).

*Alternatives:* steps as a transformable `[String]` — fewer entities, but two representations for two lists of the same shape, and CloudKit stores it as an opaque blob. A single JSON blob per recipe — cannot be queried, and every ingredient edit rewrites the whole record. Editing the model in place — breaks existing stores at open.

### Ingredients are matched exactly the way duplicates are

Each ingredient stores `normalizedName` computed by `GroceryItem.normalize` at save time, and status compares it to At Home rows' `normalizedName` — exact equality, no fuzzy matching, the same contract the duplicate warning already makes. Two rows in one recipe that normalize alike are merged on save (counts summed, first row's name and position kept), mirroring the one-row-per-name invariant. Blank rows are dropped.

The cost of exact matching is spelling drift ("ground beef" vs "beef") turning a cookable recipe into an x. The mitigation is the editor's inline "you have N at home" note under each ingredient name, reusing `GroceryStore.findItem` exactly as `ItemEditorView` does — the user sees the match happen while typing.

### Status is a pure function over an inventory dictionary

`RecipeAvailability` (`nonisolated`, no Core Data import beyond the model types) takes `[normalizedName: quantity]` and a recipe's ingredients and returns per-ingredient shortfalls plus `canMake`. Views build the dictionary once from a `@FetchRequest` of At Home items scoped to the household; `RecipesView` and `RecipeDetailView` each hold one, so both update live when the inventory changes (the "status follows the inventory" and "control becomes enabled" scenarios fall out of `@FetchRequest`). Cost is O(total ingredients) per evaluation, sub-millisecond for hundreds of recipes.

The **filter** is an in-memory `filter` over the fetched recipes by `canMake`. No predicate can express it (it is a cross-entity aggregate), and none is needed.

*Alternative rejected:* a persisted `canMake` attribute recomputed on every inventory write — write amplification on every check-off, sync churn, and wrong on the device that has not received the inventory change yet.

### Grid: `ScrollView` + `LazyVGrid`, sorted by name

Adaptive columns (minimum ~150 pt; two columns at the Mac's 480 pt floor, two to three on iPhone). Recipes come from a `@FetchRequest` sorted by `name` with `localizedCaseInsensitiveCompare:`, which the SQLite store supports. Tiles observe their `Recipe` so an edit re-renders them; the editor replaces child rows wholesale on save, so an ingredient change is visible as a relationship change. Name order rather than the items' `createdAt` order because a recipe collection is browsed, not watched while editing.

Lazy rendering is what makes "infinite scroll" free: only visible tiles exist, and Core Data faults rows on demand. No paging.

### Images: ImageIO in, ≤1024 px JPEG stored, decoded once and cached

`RecipeImage` (`nonisolated`) wraps ImageIO: `CGImageSourceCreateThumbnailAtIndex` with a max pixel size of 1024 and `kCGImageSourceCreateThumbnailWithTransform` (bakes in EXIF orientation), written back as JPEG around quality 0.8 — typically 100–300 KB. It also decodes stored bytes to a `CGImage` for display via `Image(decorative:scale:)`, cross-platform with no UIKit/AppKit. Both functions are pure and unit-testable.

Selection uses `PhotosPicker` (PhotosUI, iOS 16+/macOS 13+, out-of-process — no `NSPhotoLibraryUsageDescription`) and `loadTransferable(type: Data.self)`; HEIC is fine since ImageIO reads it on every platform.

A small `NSCache<NSString, CGImage>` keyed by object-ID URI plus byte count avoids re-decoding tiles as they scroll back into view; a same-size byte-identical replacement is the only miss case and is negligible.

*Alternative rejected:* storing the original photo — multi-megabyte assets on every sync and in memory for every tile.

### The cooking session is view state, presented as a sheet

`CookingSessionView` holds two `@State` sets of checked indexes. A session exists only while presented, so "clean slate every time" and "nothing persists across relaunch" are properties of the presentation, not features to build. Presented with `.sheet` on every platform (`fullScreenCover` is iOS-only), inside a `NavigationStack` with Cancel as `cancellationAction` (Escape on the Mac) and Finish Cooking as `confirmationAction`. `.interactiveDismissDisabled` turns on once anything is checked, so a swipe-down cannot end a session in progress; before that, swipe-down is just cancel.

*Alternative rejected:* a persisted `CookingSession` entity — nothing worth syncing, stale sessions to garbage-collect, more model surface.

### Finish Cooking is `checkOff` in reverse, with per-line verification

`RecipeStore.consume(recipe)` walks the ingredients, decrements each matching At Home row via the same delete-at-zero rule `GroceryStore.setQuantity` enforces, skips absent rows, and returns a `CookUndo` value: recipe name, household ID, and one line per ingredient recording name, normalized name, category, manual flag, the delta, and the outcome (`reduced(expected:)` or `removed`). `undoConsume` re-fetches each line: a row holding the expected quantity gets the delta back; a row that should be absent and is absent is recreated with its recorded name, category, and flag; anything else is left alone and named in the result. Same three-outcome discipline as `undoCheckOff` (never treat a missing row as quantity 0). The banner lives on `RecipeDetailView`, view-local like the shopping list's, using `UndoBannerView` and `LaunchSupport.confirmationDuration`.

*Why not `UndoManager`:* same reason as check-off — the reversal has to know this specific cook produced the delta, and it needs a visible affordance.

### Start Cooking is disabled, not hidden

User decision. Disabled beats hidden: the button stays discoverable and the x-marked ingredients directly above it explain the state, whereas a hidden button leaves the user wondering if the feature exists. Recorded in cerebrum as a scoped exception to "warn, never block".

### Add Missing tops the list up; it does not add blindly

For each short ingredient, `shortfall = count − atHome`; the list row is raised to `max(current, shortfall)` via `GroceryStore.findItem` + `addItem`'s merge path. Idempotent by construction — a second tap changes nothing — and never over-buys, which matters in an app whose purpose is not buying what you don't need. No duplicate warning: the warning exists to surface at-home stock, and the shortfall is computed from it. Categorization happens in `GroceryItem.create` (static table, as always).

*Alternative rejected:* adding the shortfall unconditionally — a double tap or a revisit doubles the purchase.

### Delete with undo via a value snapshot

`RecipeStore.delete` returns a `RecipeSnapshot` (name, summary, image bytes, ingredient tuples, step strings, household ID); `undoDelete` recreates the graph. The banner lives on `RecipesView`. Cascade handles the children. *Alternative rejected:* a soft-delete flag — leaks into every fetch predicate and syncs tombstones forever.

### Target membership: logic in, UI out

Model classes, `RecipeStore`, `RecipeAvailability`, and `RecipeImage` join the watch target by default (no exception entry) so the watch's Core Data stack can map the new entities; `RecipeImage` imports only ImageIO, which watchOS has. Every new view file is added to the watch target's `PBXFileSystemSynchronizedBuildFileExceptionSet`. The watch UI is untouched.

### Mac idioms follow the existing pattern

Tiles get a `.contextMenu` (Edit, Delete) on every platform; ⌘N opens the editor from the Recipes tab like the other tabs; the detail toolbar carries Edit and a Delete item; sheets get a `minWidth`/`minHeight` on macOS so the editor and session are usable at the 480 pt window floor. The grid is not a `List`, so the macOS multi-section mis-diff does not apply, but the Mac is built and driven early precisely because "compiles on macOS" has surprised this project before.

### Verification: unit tests carry the logic, seeded UI tests carry the flows

Swift Testing covers `RecipeAvailability`, ingredient merging, `consume`/`undoConsume` in all three outcomes, `delete`/`undoDelete`, add-missing idempotence, and the image bound. `LaunchSupport` seed `1` gains two recipes — "Buttered Toast" (Butter ×1, cookable with the seeded Butter ×1 at home) and "Onion Soup" (Onion ×3 + Butter ×1, an x, because the seeded onions are on the list, not at home) — with no new items, so existing UI-test assertions hold. iOS XCUITests cover tab, tiles, filter, detail marks, disabled Start Cooking, top-up (the seeded "Onion" ×2 list row becomes ×3), session toggling and clean slate, finish and undo, create, delete and undo. The Mac binary is launched with the seed env and driven directly. Hardware confirms sync, sharing, and migration over the phone's existing data.

## Risks / Trade-offs

- [Production schema not deployed before TestFlight] → task 7 gates the upload on a CloudKit Console check that `CD_Recipe`, `CD_RecipeIngredient`, `CD_RecipeStep` exist in production; local use is unaffected either way, and mirroring retries once the types appear.
- [An older TestFlight build receives unknown record types] → `NSPersistentCloudKitContainer` skips records for entities its model lacks; the only affected users are this household, who update together. Verified on the phone before the store is touched by a new build.
- [Lightweight migration on real data] → additive change; confirmed by installing the new build over the user's existing TestFlight data and checking items and household survive (task 7.5). Rollback: the old build ignores the new record types; item data is never rewritten.
- [Spelling drift makes recipes show x] → exact matching is the app's stated contract; the editor's inline at-home note is the mitigation. If it bites, a later change could add a "did you mean" against inventory names.
- [Image memory and scroll stalls] → 1024 px bound, JPEG, lazy grid, decode cache. If scrolling still stalls with hundreds of photos, drop the cache limit or add a 320 px thumbnail attribute — both spec-neutral.
- [Concurrent inventory edits during a cook] → last-writer-wins, the same accepted v1 limitation as check-off; undo verifies per line and reports what it left alone.
- [`PhotosPicker` presentation quirks on macOS] → known to work on macOS 13+; verified in the driven Mac pass, with a fallback to `.fileImporter` for images if the picker misbehaves in a sheet.
- [Watch build breaks from a forgotten exception entry] → task 4.9 builds the watch target immediately after the last view file lands.

## Migration Plan

1. Add model version 2 and the subclasses; build all three destinations.
2. Run the app on the user's iPhone with `PUSH_CK_SCHEMA=1` once to push the three record types to the development schema; confirm in CloudKit Console.
3. Implement and verify against the development environment (dev-signed builds, per the existing sync note).
4. Deploy schema changes to production in CloudKit Console.
5. Upload the TestFlight build; install over existing data; confirm items intact and recipes syncing.

Rollback: revert to the previous build. The v1 model still opens the store (migration was additive), and unknown record types in CloudKit are ignored.

## Open Questions

- Placeholder artwork: a symbol-based placeholder ships; whether to commission an illustration is a later, spec-neutral choice.
