## Context

`nomorewaste` is currently an empty SwiftUI app: a single `nomorewaste/ContentView.swift` holding both the `@main` entry point and a "Hello, world!" view. There is no data layer, no navigation, and no test target.

Relevant facts about the target, confirmed from `nomorewaste.xcodeproj/project.pbxproj`:

- **Deployment target is currently iOS 27.0 and will be lowered to iOS 18.0.** The current value restricts installs to devices on the newest OS for no benefit. Everything this design relies on — `NSPersistentCloudKitContainer` record-zone sharing, `ShareLink` with `CKShareTransferRepresentation` — has been available since iOS 15/16.
- **File-system synchronized groups** (`PBXFileSystemSynchronizedRootGroup`). Any `.swift` file dropped into `nomorewaste/` joins the target automatically — no `project.pbxproj` editing is needed to add source files. Adding a *new target* (e.g. unit tests) would still require project edits, as would adding capabilities.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** with `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Types are main-actor-isolated by default. Core Data background contexts must therefore be handled deliberately rather than assumed.
- **Single app target, no test target**, and `SUPPORTED_PLATFORMS` includes macOS and visionOS.

**Account constraint:** CloudKit requires a paid Apple Developer Program membership — free personal-team provisioning cannot grant the iCloud entitlement, on device or in the simulator. The membership was approved on 2026-07-21, so this no longer constrains the build. What remains is that realistic sharing verification needs two iCloud accounts on two physical devices.

This design covers a new data model, a new offline classification component, an entire UI, and cross-user sync, so it is worth settling the shape before writing code.

## Goals / Non-Goals

**Goals:**

- One item catalog with two views over it, so the shopping list and the home inventory can never disagree about what the user owns.
- Categorization that is instant, deterministic, offline, and legible to a developer reading the table — no AI, no network, no inference.
- A check-off flow that costs one tap in the common case and is always reversible: transiently via undo, permanently via move-back.
- Duplicate awareness delivered at the moment of decision without ever blocking the user from buying more.
- Offline-first sync: the app is fully functional with no connection, and converges when one returns.
- Household sharing with no account system — invite by iCloud, read-write for everyone, no sign-up screen.
- A persistence layer whose CloudKit compatibility is enforced by the runtime from the first store load, not by a checklist.
- Few enough files that the whole app stays readable.

**Non-Goals:**

- Expiration dates, shelf-life estimates, freshness badges, notifications.
- Non-Apple platforms. Using the iCloud account as identity rules out Android and web permanently; that is an accepted ceiling.
- Per-member permissions, roles, or read-only participants.
- Recipes, meal planning, barcode scanning, store aisle ordering, price tracking.
- Units of measure, fractional quantities.
- A general undo stack; only the most recent check-off is reversible via the undo control, and only while the shopping list is on screen.
- Belonging to more than one shared household. A user has their personal household and at most one joined household; accepting a second invitation while already in one is undefined here.
- Conflict-free replicated quantities. See the last-writer-wins decision below.

## Decisions

### Core Data with `NSPersistentCloudKitContainer`, not SwiftData

*This reverses an earlier decision in this document's history.* Before sharing was a requirement, SwiftData was the right call — less ceremony, `@Query` for free. Sharing is precisely the requirement that invalidates it: **SwiftData mirrors only the private CloudKit database.** `CKShare` against the shared scope requires `NSPersistentCloudKitContainer`, and Apple's own guidance is to use Core Data for shared or public databases. Running SwiftData for local data and Core Data for shared data means two stacks over one dataset.

The stack: `NSPersistentCloudKitContainer` with **two store descriptions** — one at `.private` scope, one at `.shared` — each backed by its own SQLite file, both with persistent history tracking and remote change notifications enabled (both are required for CloudKit mirroring). Views read via `@FetchRequest`; multi-row writes go through a store layer.

*Alternative considered:* SwiftData now, migrate later. Rejected outright — that is the migration this decision exists to avoid, and it would have to happen after users have data.

### A `Household` root entity, shared as one unit

`CKShare` shares a record *and the object graph beneath it*. Modeling an explicit `Household` entity that owns every `GroceryItem` makes sharing a single natural operation: share the `Household`, and all items — list and inventory alike — travel with it.

Every install creates exactly one local `Household` on first launch. `GroceryItem` has a required `household` relationship.

The persistence controller exposes an **`activeHousehold`**, and every item fetch in the app scopes to it. Before sharing exists there is only one household, so this looks redundant — it is not. Accepting an invitation means a second `Household` arrives in the shared store while the personal one stays in the private store, and any fetch written without that predicate would then show both households' items merged into one list. Introducing the predicate later means revisiting every fetch and every view; introducing it now means joining a household is a one-line change to what `activeHousehold` points at.

*Why the household and not the list:* the proposal's non-negotiable is that an invited member sees the same inventory, not just the same list. Sharing only the shopping list would leave them comparing it against their own empty inventory, so the duplicate warning — the entire point of the app — would silently mislead exactly the person who was invited to avoid buying duplicates.

*Alternative considered:* sharing individual items. Rejected — it makes every add a sharing decision and produces an incoherent partial inventory.

### Quantities are last-writer-wins, and that is a known limitation

`NSPersistentCloudKitContainer` merges field-by-field with `NSMergeByPropertyObjectTrumpMergePolicy` — last writer wins per property. Quantity mutation is `quantity += N`, a read-modify-write, which is the classic operation this breaks: two members checking off the same item before a sync round-trip lose one of the increments.

The failure mode is "the inventory says 3 onions when the kitchen has 5" — the exact error the app exists to prevent, so it is not cosmetic. It is nonetheless **accepted for v1**: the conflict window is the seconds between two members acting on the same item, the inventory is hand-correctable in one tap, and the alternative is real complexity.

*The upgrade path if it bites:* model quantity as the sum of immutable `QuantityAdjustment` records (+2, −1, …) rather than a mutable integer. Inserts never conflict in CloudKit, so the sum is correct regardless of ordering. Cost: a second entity, derived reads, and periodic compaction — which is why it is not in v1.

*Alternative considered:* building the adjustment-record model up front. Rejected as premature for an app whose thesis is simplicity, but the `GroceryStore` boundary below is drawn so that this swap touches one file.

### Sharing UI: `ShareLink`, not `UICloudSharingController`

The sending side uses SwiftUI's `ShareLink` with `CKShareTransferRepresentation`, avoiding a `UIViewControllerRepresentable` wrapper around `UICloudSharingController`. Acceptance requires `CKSharingSupported` in Info.plist and a `UIApplicationDelegateAdaptor` implementing `application(_:userDidAcceptCloudKitShareWith:)` — SwiftUI has no native hook for share acceptance, so a minimal app delegate is unavoidable.

### Store both `name` and `normalizedName` on the record

`name` is what the user typed and what is displayed. `normalizedName` is derived and stored alongside it, recomputed on every write.

*Why:* duplicate detection is a lookup by normalized name on every keystroke in the add field. A stored, indexed field makes that a fetch predicate rather than an in-memory scan with per-item string processing.

Normalization: trim → collapse whitespace → lowercase → strip punctuation → fold a trailing plural. The plural fold is applied **identically to stored names and to lookup queries**, which makes an imperfect stemmer harmless: "asparagus" folding to "asparagu" still matches itself. Only exact equality of normalized names counts as a duplicate — no fuzzy or prefix matching, so "onion" never collides with "green onion".

### Categorization is a static keyword dictionary, matched rightmost-first

A `GroceryCategory` enum (Produce, Dairy & Eggs, Meat & Seafood, Bakery, Frozen, Pantry, Beverages, Snacks, Household Goods, Other) with a fixed `displayOrder`, and a `CategoryClassifier` holding a compiled-in `[String: GroceryCategory]` table of roughly 200–300 common grocery terms.

Matching order: exact whole-name match → **the keyword ending latest in the name, matched on word boundaries** → `.other`. Two keywords ending at the same position resolve by length, then by the fixed category order, so the result never depends on dictionary iteration.

*Why rightmost:* an earlier draft ran "any single word" before "longest contained keyword", which left the common case undecided — "apple juice" matches `apple` and `juice`, "potato chips" matches `potato` and `chips`, and nothing in the rule said which wins. English builds grocery names as modifier-then-head-noun, so the last matching keyword is what the item *is*: "chocolate milk" is milk, "milk chocolate" is candy. Length as the tiebreak at equal end position is what lets a multi-word key win over the word inside it — `ice cream` beats `cream` in "vanilla ice cream" because both end at the same place and `ice cream` is longer. Requiring word-boundary matches is what makes a single stage safe: it is the reason "**bar**becue sauce" cannot hit `bar`, which is what the old two-stage ordering existed to prevent.

*Why a table at all:* the requirement is explicitly no AI, and a table is also the right engineering answer — instant, offline, trivially correctable, and predictable to a developer reading it. Categorization stays entirely local even after sync is added; it never depends on the network.

**The table's keys must be normalized, not naturally spelled.** `classify` normalizes its input first, and normalization folds a trailing plural — so "asparagus" arrives as `asparagu` and a key written `"asparagus"` matches nothing at any stage. The same trap catches chips, crackers, pretzels, nuts, hummus, couscous, molasses, and brussels sprouts, and it fails silently into Other. Run every key through the same normalizer when the table is built rather than hand-writing folded keys, which are unreadable and easy to get wrong.

*Alternatives considered:* on-device `NLTagger`/embedding similarity — rejected, both because it is the class of thing the requirement excludes and because it is unpredictable for the short, modifier-heavy strings groceries produce. A user-editable dictionary — deferred; the sticky manual override covers the same need per item with far less UI.

### The "Household" category is `householdGoods` in code

The fixed category set includes Household (paper towels, detergent), and the sharing root entity is also called `Household`. Left alone, the app would carry both `item.household` (the relationship to the sharing root) and `item.category == .household` (the category for dish soap), which is the kind of collision that produces a confident wrong reading months later.

The enum case is therefore `householdGoods` while its `displayName` stays "Household". Users see the shorter word; the code cannot conflate the two.

### Manual category override pins the item

A `categoryIsManual: Bool` on the record. Automatic classification runs on create and on rename only while the flag is false. Setting a category by hand sets the flag; an explicit "Automatic" option clears it and immediately reclassifies.

*Why:* silently re-deriving a category the user just corrected is the most annoying possible behavior, and the flag is one field. The escape hatch back to automatic keeps the pin from being a trap.

### Undo is an explicit snapshot that verifies before reversing

Check-off produces a value-type `CheckOffUndo` record held in view state: the item's name, quantity, category, manual flag, **how the write landed** (flipped this item's location, or merged N into existing home item X and deleted the list row), and **the home item's expected quantity immediately after the check-off**.

Undo reverses precisely the recorded branch — but first re-fetches the home item and compares its current quantity against the expected value. If they differ, the record was changed on another device or by another household member in the interim, and blindly subtracting N would destroy their edit. In that case undo **restores the shopping-list row** (unambiguously what the user asked for) but **leaves the home quantity untouched**, and says so.

The re-fetch has three outcomes, not two: quantity matches, quantity differs, or **the item is gone**. Gone is the likelier of the two failure paths, not an edge case — decrementing to zero deletes the row, so any member finishing off the milk produces it. It takes the same branch as a mismatch: restore the list row, recreate nothing at home, report that it changed elsewhere. Treating a nil fetch as "quantity 0" and proceeding would resurrect a row someone deliberately used up.

The banner itself is view state on the shopping list, and leaving that screen dismisses it. This is a deliberate scope limit rather than an oversight: hoisting undo state above the `TabView` to survive tab switches would add shared mutable state across both screens to protect a five-second window whose permanent replacement — move-back-to-list — already exists and is a normal feature.

*Why not `UndoManager`:* the merge branch is what rules it out. Reversing "quantity went 3 → 5" correctly requires knowing that 2 came from this specific check-off, not resetting to a remembered absolute value that a concurrent edit may have invalidated. Sharing makes that concurrent edit likely rather than theoretical. An explicit delta snapshot plus a verification read is unambiguous, and it gives us a visible affordance that shake-to-undo does not.

*Alternative considered:* a persisted, cross-device undo history. Rejected as over-scope — the permanent recovery path is "move back to shopping list" from the inventory, a normal feature the specs require independently.

### Duplicate warning: inline note while typing, confirm alert on commit

Two affordances, deliberately:

1. **Inline note** under the name field, live as the user types, when the normalized name matches an at-home item — "You have 3 at home". Non-modal, never steals focus.
2. **Confirmation alert** on save when that condition holds — states the count, offers "Add Anyway" and "Cancel", and Cancel returns to the sheet with the typed values intact.

Both read the household's inventory, so an invited member gets the same warning from the same numbers as the owner. The count reflects the last synced state; a stale count is possible but strictly better than no count.

*Why both:* the inline note is the seamless path — most users see it, adjust, and never meet the alert. But typing fast and hitting Save is exactly the moment the note gets missed, and the requirement is that the user is *made aware*. The alert costs one extra tap and only in the duplicate case, which is the one case worth a tap.

### Screen structure

```
nomorewaste/
  NoMoreWasteApp.swift      @main, TabView shell, app delegate for share acceptance
  PersistenceController.swift  NSPersistentCloudKitContainer, private + shared stores
  Household.swift           root entity owning all items
  GroceryItem.swift         entity, ItemLocation, normalization
  GroceryCategory.swift     enum, display order, SF Symbol per category
  CategoryClassifier.swift  keyword table + matching
  GroceryStore.swift        merge / check-off / move-back / undo operations
  SharingController.swift   CKShare creation, participant list, leave/stop sharing
  ShoppingListView.swift    sectioned list, check-off, undo overlay
  HomeInventoryView.swift   sectioned list, steppers, move-back
  ItemEditorView.swift      shared add/edit sheet, duplicate warning
  HouseholdView.swift       share sheet entry, members, sync status
  CategorySection.swift     shared sectioning + row views
```

Mutations that touch more than one row — check-off, merge-on-add, move-back, undo, **and rename** — live in `GroceryStore` as functions over an `NSManagedObjectContext`, not scattered across views. This keeps the invariant "no two rows share a normalized name in the same location within a household" enforceable in one place, and it is the seam the quantity model would change behind if last-writer-wins proves insufficient.

Rename belongs in that list even though it looks like a single-row edit. Renaming "Scallion" to "Onions" on a list that already holds "Onion" produces two rows with the same normalized name, which is exactly the state the invariant forbids and which every duplicate and merge path downstream assumes cannot happen. `rename` therefore performs the same merge that `addItem` does, with the pre-existing row surviving and keeping its display name, category, and manual flag.

### Turn sync on before writing feature code

The entitlement, container, and `cloudKitContainerOptions` are configured in the first three task groups, so `NSPersistentCloudKitContainer` is genuinely mirroring by the time the classifier and the store operations are written.

*Why not build locally first and enable sync at the end:* the model constraints CloudKit imposes — every attribute optional or defaulted, no unique constraints, every relationship inversed — are not enforceable by inspection. With mirroring on, a violation throws at store load, on the commit that introduced it. With mirroring off, the same violation is silent until the end of the build, by which point the store operations, the fetches, and the duplicate-warning logic have all been written against a model that has to change.

The cost is a resettable one: schema iteration happens in CloudKit's **development** environment, which can be reset wholesale. The irreversible constraint is only the production schema, which nothing touches until the first TestFlight push.

Sharing (the `.shared` store description, share acceptance, the sharing UI) is still built last — not because it is blocked, but because it depends on the household model being settled.

### Verification without a test target

The project has no test target, and adding one requires `project.pbxproj` changes that synchronized groups do not cover. `CategoryClassifier` and the name normalizer are written as pure functions on plain types with no Core Data or SwiftUI dependency, and are exercised from a `#Playground` block covering the classification and normalization scenarios in the specs.

*Trade-off accepted:* the multi-row store operations get manual verification against the spec scenarios rather than automated tests. They are the most logic-dense part of the app, so this is the weakest point of the plan — flagged in Risks.

## Risks / Trade-offs

- **Lost quantity increments under concurrent check-off** → accepted for v1 as described above; surfaced in the specs as a known limitation rather than a bug, and the inventory is hand-correctable. Revisit with adjustment records if TestFlight shows it happening.

- **Sync is on during development, so schema mistakes reach CloudKit** → they reach the *development* environment, which is resettable; only the production schema is append-only. Do not push to TestFlight until the model has settled.

- **Testing sharing realistically needs two iCloud accounts and two physical devices** → simulator-to-simulator share acceptance is unreliable. Budget for this; do not treat "it compiles" as verification of the sharing flow.

- **Users with no iCloud account, or with iCloud Drive disabled, get no sync** → the app must degrade to fully-functional local-only with an honest status message, never an error state or an empty screen. The private store must work with CloudKit mirroring unavailable.

- **Keyword table will miss real groceries** (brand names, regional terms) → those land in "Other", which the specs require to be fully functional, and the sticky manual override fixes any item permanently in two taps. Seed the table from the most common ~200 terms rather than chasing coverage.

- **Plural folding could collide two genuinely different groceries** → only exact normalized equality merges anything, folding is applied symmetrically, and the fold is a conservative suffix rule rather than a real stemmer. Worst realistic case is a wrong merge on a rare word pair; the user can rename to split them.

- **Merge-on-check-off and undo are the highest-risk logic in the app, and there is no test target** → keep them in `GroceryStore` as small, single-purpose functions, and walk every check-off/undo scenario manually in the simulator. If this proves fragile, adding a unit-test target is the first follow-up.

- **The confirmation alert could feel like nagging** for users who intentionally rebuy staples → it fires only when the item is genuinely at home with quantity ≥ 1, never repeats within a single add, and "Add Anyway" is the primary action. Fallback is dropping to the inline note alone, which the design keeps as an independent piece.

- **iCloud-as-identity is a permanent platform ceiling** → no Android, no web, ever, without adding a real backend and auth system. Accepted deliberately in exchange for having no account system at all.

- **Shared records count against the household owner's iCloud quota** → negligible for text records at this scale, but it means the cost is asymmetric between owner and participants.

- **macOS/visionOS are in `SUPPORTED_PLATFORMS`** but the design targets iPhone interaction (swipe-to-delete, bottom undo overlay) → build for iOS first; standard `List` and `TabView` degrade acceptably elsewhere. No effort spent on other platforms in this change.
