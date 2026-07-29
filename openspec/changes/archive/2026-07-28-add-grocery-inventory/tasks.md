> The Apple Developer Program membership was approved on 2026-07-21, so nothing here is account-blocked. The former two-phase split is gone: entitlements are set up in group 1 and sync is on from group 3, so CloudKit validates the model while the model is still cheap to change.
> Group 12 remains gated on **two iCloud accounts and two physical devices** — that is a hardware and account constraint, not a membership one.

## 1. Project configuration

- [x] 1.1 Lower `IPHONEOS_DEPLOYMENT_TARGET` from 27.0 to 18.0 in the target's build settings.
- [x] 1.2 Replace the placeholder `PRODUCT_BUNDLE_IDENTIFIER` (currently `devplaceholder.$(PROJECT_UNIQUE_VALUE:identifier).$(PRODUCT_NAME:rfc1034identifier)`) with a real reverse-DNS identifier. A CloudKit container cannot be registered against a placeholder ID, and changing it later orphans the container.
- [x] 1.3 Confirm the membership is active and the team appears in Xcode's Signing & Capabilities.
- [x] 1.4 Add the iCloud capability with CloudKit enabled and create the CloudKit container. This generates the target's first entitlements file — confirm `CODE_SIGN_ENTITLEMENTS` is now set and lists the container.
- [x] 1.5 Add the remote-notification background mode.
- [x] 1.6 Confirm the app still builds, signs, and runs in the simulator after the target, bundle ID, and capability changes.

## 2. Foundation: model and categories

- [x] 2.1 Create `nomorewaste/GroceryCategory.swift`: `enum GroceryCategory: String, CaseIterable` with cases produce, dairyAndEggs, meatAndSeafood, bakery, frozen, pantry, beverages, snacks, **householdGoods**, other; a `displayName`, an `sfSymbol`, and a `sortOrder` matching the fixed order with `.other` last. The case is `householdGoods`, not `household`, so it cannot be confused with the `Household` entity — `displayName` is still "Household".
- [x] 2.2 Create the Core Data model (`nomorewaste/NoMoreWaste.xcdatamodeld`) with a `Household` entity and a `GroceryItem` entity, and a `household` ↔ `items` relationship between them (to-one from the item, to-many from the household, each set as the other's inverse).
- [x] 2.3 Give `GroceryItem` attributes: `name`, `normalizedName`, `quantity` (Integer 64), `categoryRawValue`, `locationRawValue`, `categoryIsManual` (Boolean), `createdAt`.
- [x] 2.4 Give `Household` attributes: `id` (UUID) and `createdAt`. It needs no name — the member list comes from the `CKShare`'s participants, not from stored fields. `id` gives the app a stable way to record which household is active.
- [x] 2.5 Make the model CloudKit-compatible: every attribute optional or carrying a default value, no unique constraints, and every relationship with a defined inverse. With sync on from group 3, a violation throws at store load rather than surfacing months later.
- [x] 2.6 Create `nomorewaste/Household.swift` with the `Household` `NSManagedObject` subclass and its `items` relationship accessor.
- [x] 2.7 Create `nomorewaste/GroceryItem.swift` with the `NSManagedObject` subclass, `enum ItemLocation: String { case shoppingList, atHome }`, and computed `category` / `location` accessors over the raw string attributes.
- [x] 2.8 Add a static `GroceryItem.normalize(_:) -> String` implementing trim → collapse whitespace → lowercase → strip punctuation → fold trailing plural, and make every write path that sets `name` also set `normalizedName` from it.
- [x] 2.9 Add a convenience creator taking name/quantity/location/household that derives `normalizedName` and classifies the category, so no caller can construct an inconsistent record.

## 3. Persistence stack

- [x] 3.1 Create `nomorewaste/PersistenceController.swift` wrapping `NSPersistentCloudKitContainer` — the CloudKit-capable container type, used now with a purely local configuration.
- [x] 3.2 Enable `NSPersistentHistoryTrackingKey` and remote-change notifications on the private store description. These must be on from the first release; retrofitting history tracking after data exists is painful.
- [x] 3.3 Attach `cloudKitContainerOptions` to the private store description, pointing at the container from 1.4.
- [x] 3.4 Push the schema to the CloudKit **development** environment with `initializeCloudKitSchema()`, behind a `#if DEBUG` + explicit opt-in flag so it never runs in a shipping build. The app shell does not exist until group 6, so drive this from a `#Playground` block or a temporary call in `ContentView`.
- [x] 3.5 Resolve any model-compatibility failures 3.4 surfaces before writing feature code — these are the 2.5 constraints failing at runtime, and they are cheapest to fix now.
- [x] 3.6 Set the merge policy to `NSMergeByPropertyObjectTrumpMergePolicy` and enable `automaticallyMergesChangesFromParent` on the view context.
- [x] 3.7 On first launch, create exactly one `Household` if none exists, with no prompt or setup step.
- [x] 3.8 Expose an `activeHousehold` on the controller and inject it into the environment. **Every item fetch in the app scopes to it.** Group 11 changes which household is active; it must not have to add a predicate to fetches that were written without one.
- [x] 3.9 Define how `activeHousehold` resolves at launch: if a household exists in the shared store, it is active; otherwise the personal household from 3.7 is. Persist the chosen `Household.id` in `UserDefaults` so the choice survives relaunch and does not flip when a sync arrives mid-session.
- [x] 3.10 Add an in-memory store variant for SwiftUI previews.
- [x] 3.11 Confirm the stack still loads and every screen works with no iCloud account signed in — sync off, app fully usable.

## 4. Offline categorization

- [x] 4.1 Create `nomorewaste/CategoryClassifier.swift` with a compiled-in `[String: GroceryCategory]` keyword table seeded with ~200–300 common grocery terms spread across all nine non-Other categories. Write the keys in their natural spelling.
- [x] 4.2 **Build the lookup table by running every key through `GroceryItem.normalize`.** `classify` normalizes its input, and normalization folds trailing plurals, so a raw key of `"asparagus"` (which normalizes to `asparagu`) can never match. Same for chips, crackers, pretzels, nuts, hummus, couscous, molasses. This fails silently into `.other`, so add an assertion that no two natural keys collide after folding.
- [x] 4.3 Implement `classify(_ name: String) -> GroceryCategory` applying, in order: exact normalized-name match → the keyword whose last character falls latest in the name, matched **on word boundaries only** → `.other`. Break same-end-position ties by keyword length, then by `sortOrder`, so results never depend on dictionary iteration order.
- [x] 4.4 Confirm the classifier imports no network, ML, or AI framework and performs no I/O — it must stay a pure function over the compiled table even after sync is added.
- [x] 4.5 Add a `#Playground` block exercising the spec scenarios: "Broccoli"→produce, "organic baby spinach"→produce, "2% milk"→dairyAndEggs, "Zorbex"→other; the rightmost-match cases "potato chips"→snacks (not produce), "apple juice"→beverages, "chocolate milk"→dairyAndEggs vs "milk chocolate"→snacks; the same-end-position case "vanilla ice cream"→frozen (`ice cream` beats `cream`); the word-boundary case "barbecue sauce"→pantry (never `bar`→beverages); the folded-key cases "Asparagus"→produce and "Tortilla Chips"→snacks; plus normalization cases "  broccoli  " == "Broccoli", "onions" == "onion", "green onion" != "onion".
  - Note: "ice cream"→frozen is resolved by the *exact whole-name* stage and does not exercise rightmost matching at all — "vanilla ice cream" is the case that does. The earlier version of this task tested the wrong stage.

## 5. Store operations

- [x] 5.1 Create `nomorewaste/GroceryStore.swift` with a `findItem(normalizedName:location:household:in:)` fetch used by every duplicate and merge path.
- [x] 5.2 Implement `addItem(name:quantity:location:household:context:)` that merges into an existing row with the same normalized name in the same location instead of creating a duplicate.
- [x] 5.3 Implement `setQuantity` / `adjustQuantity` that delete the item when the quantity would reach zero or below, so no zero-quantity row can ever be stored.
- [x] 5.4 Implement `checkOff(_:context:) -> CheckOffUndo` that either flips `location` to `.atHome` or, when a home row with the same normalized name exists, adds the quantity to it and deletes the list row — returning a `CheckOffUndo` recording the name, quantity, category, manual flag, which branch ran, and the home item's expected quantity after the write.
- [x] 5.5 Implement `undoCheckOff(_:context:)` reversing exactly the recorded branch, but first re-fetching the home item and comparing its quantity to the recorded expected value.
- [x] 5.6 When that comparison fails, restore the shopping-list row, leave the home quantity untouched, and return a result the UI can use to tell the user the item was changed elsewhere.
- [x] 5.7 **Handle the re-fetch returning nothing** — the home item was deleted or decremented to zero by another member. This is the likelier failure path, not an edge case. Take the same branch as 5.6: restore the list row, recreate nothing at home, report "changed elsewhere". Do NOT treat a missing item as quantity 0 and proceed, which would resurrect a row someone deliberately used up.
- [x] 5.8 Implement `moveBackToShoppingList(_:context:)` preserving name, quantity, category, and manual flag, merging into an existing shopping-list row when one matches.
- [x] 5.9 Implement `rename(_:to:context:)` that recomputes `normalizedName`, and reclassifies the category only when `categoryIsManual` is false.
- [x] 5.10 **Make `rename` merge on collision.** Renaming into a name already used in the same location within the household would otherwise create the duplicate row the whole model forbids. Reuse the 5.1 lookup: fold the renamed item's quantity into the pre-existing row, delete the renamed row, and keep the survivor's display name, category, and manual flag. Applies on both screens.
- [x] 5.11 Implement `setCategory(_:manual:)` and a "revert to automatic" path that clears the manual flag and immediately reclassifies from the current name.

## 6. App shell

- [x] 6.1 Replace `nomorewaste/ContentView.swift` with `nomorewaste/NoMoreWasteApp.swift`: `@main`, a `TabView` with "Shopping List" and "At Home" tabs, Shopping List selected on launch, and the managed object context injected into the environment.
- [x] 6.2 Delete the placeholder `ContentView` and its preview; confirm the new files were picked up automatically by the synchronized file group and the app builds and launches.

## 7. Shared UI pieces

- [x] 7.1 Create `nomorewaste/CategorySection.swift` with a helper that groups fetched items into category sections ordered by `sortOrder`, omitting empty categories. **Within a section, sort by `createdAt` ascending** — newly added items append to the bottom rather than reordering rows the user is looking at. Every `@FetchRequest` in the app uses this same sort so the two screens never disagree.
- [x] 7.2 Build a reusable row view showing name, quantity, and an inline stepper that adjusts quantity in place without navigation.
- [x] 7.3 Build a reusable empty-state view taking a message and an optional add action.

## 8. Screens, editor, and duplicate warning

- [x] 8.1 Create `nomorewaste/ItemEditorView.swift` as a sheet handling both add and edit, with a name field, a whole-number quantity stepper defaulting to 1, and a category picker including an "Automatic" option.
- [x] 8.2 Reject saving a blank or whitespace-only name, keeping the field active rather than dismissing.
- [x] 8.3 Add the live inline on-hand note beneath the name field: as the typed name normalizes to a match against an `.atHome` item with quantity ≥ 1, show "You have N at home"; hide it as soon as the name stops matching. It must not steal focus, block saving, or wait on the network.
- [x] 8.4 On save of a shopping-list item that matches an at-home item, present a confirmation alert naming the item and its on-hand count, with "Add Anyway" as the primary action and "Cancel" returning to the sheet with the typed name and quantity intact. **The alert fires on the merge path too** — when the name already has a row on the shopping list, an existing list row does not tell the user what is sitting at home, which is the fact the warning exists to deliver. Only at-home stock gates the alert; a list-only match stays silent.
- [x] 8.5 Apply the same warning to a rename that makes an existing list item match an at-home item.
- [x] 8.6 Create `nomorewaste/ShoppingListView.swift` with a fetch filtered to `.shoppingList` **and to the active household from 3.8**, rendered as category sections with empty categories hidden, plus a toolbar add button and row-tap to edit.
- [x] 8.7 Add swipe-to-delete that removes the item without adding anything to the inventory, and single-tap check-off calling `GroceryStore.checkOff` with no confirmation dialog.
- [x] 8.8 Add the undo overlay: a bottom banner naming the checked-off item with an Undo action, auto-dismissing after ~5 seconds, manually dismissible, always referring to the most recent check-off — including the "changed elsewhere" message path from 5.6 and 5.7. Keep the `CheckOffUndo` in `ShoppingListView`'s own state; leaving the tab dismisses the banner, and "Move to Shopping List" is the permanent recovery path. Do not hoist it above the `TabView`.
- [x] 8.9 Create `nomorewaste/HomeInventoryView.swift` with a fetch filtered to `.atHome` **and to the active household**, sectioned the same way, with steppers that persist immediately and remove the item at zero.
- [x] 8.10 Add row-tap to edit on the At Home screen, opening `ItemEditorView` so an inventory item can be renamed and recategorized — a rename with no manual category reclassifies from the new name.
- [x] 8.11 Add swipe-to-delete and a "Move to Shopping List" row action calling `GroceryStore.moveBackToShoppingList`.
- [x] 8.12 Add a toolbar add button on the At Home screen presenting `ItemEditorView` in `.atHome` mode, without the duplicate warning path.
- [x] 8.13 Add both empty states: guidance to add a first item on the list, and an explanation that checked-off items land in the inventory.

## 9. Local verification

- [x] 9.1 Check off an item with nothing matching at home; confirm it leaves the list and appears at home with the same quantity and category.
- [x] 9.2 Check off "Onion" ×2 with 3 onions already at home; confirm a single home row shows 5.
- [x] 9.3 Undo each of the two check-off branches; confirm the create branch leaves nothing at home and the merge branch restores exactly 3, with the list row back at its original quantity.
- [x] 9.4 Edit the home quantity between check-off and undo; confirm undo restores the list row, leaves the home quantity alone, and reports that it changed elsewhere.
- [x] 9.5 Let the undo banner expire; confirm nothing changes afterward and the item is still recoverable via "Move to Shopping List".
- [x] 9.6 Add an item already at home; confirm the inline note shows the count, the alert states the count, "Add Anyway" adds with the entered quantity and leaves the inventory untouched, and "Cancel" preserves the typed values.
- [x] 9.7 Confirm a manually categorized item keeps its category through a rename, and that reverting it to Automatic reclassifies immediately.
- [x] 9.8 Add "onions" ×1 while the list already holds "Onion" ×2; confirm one row showing 3 rather than a second row. Repeat the equivalent move-back merge from the inventory.
- [x] 9.9 Rename an automatically categorized inventory item; confirm it recategorizes from the new name and moves section.
- [x] 9.10 Delete the home item entirely between check-off and undo; confirm undo restores the list row, does not recreate the home row, and reports that it changed elsewhere (5.7).
- [x] 9.11 Rename a list item into a name another list row already uses; confirm one merged row with the combined quantity and the pre-existing display name and category. Repeat on the At Home screen.
- [x] 9.12 Add an item that is already on the list *and* at home; confirm the alert still fires with the on-hand count and that Add Anyway merges into the existing list row.
- [x] 9.13 Spot-check the classifier against the table it actually shipped: "potato chips", "apple juice", "milk chocolate", "vanilla ice cream", "asparagus", "barbecue sauce". These are the cases the matching rule was rewritten for, so a wrong answer means the table or the fold is wrong, not the rule.
- [x] 9.14 Switch tabs mid-edit; confirm scroll position is kept and no in-progress entry is lost. Confirm the undo banner does not survive the tab switch and the item is still recoverable via "Move to Shopping List".
- [x] 9.15 Confirm all data survives a force-quit and relaunch, and that every flow works in airplane mode.
- [x] 9.16 Run `openspec validate add-grocery-inventory --strict` and resolve any findings.

## 10. iCloud sync verification

- [x] 10.1 Verify two devices signed into the same iCloud account converge on adds, edits, check-offs, and deletes. **Deferred 2026-07-28 (user decision):** no second device on the same iCloud account was available. Cross-account sync through the shared database is fully verified (group 12); same-account sync through the private-database mirror uses the same `NSPersistentCloudKitContainer` machinery but remains unexercised end to end. Run this check when a second same-account device exists.
- [x] 10.2 Verify offline changes on one device reconcile after reconnecting, with nothing lost.
- [x] 10.3 Verify the app degrades to fully-functional local-only with no iCloud account signed in or iCloud Drive disabled — an honest status message, never an error state or empty screen.

## 11. Household sharing

- [x] 11.1 Add a second store description at `.shared` database scope, backed by its own SQLite file, and route fetches across both stores.
- [x] 11.2 Set `CKSharingSupported`. **Correction found during implementation:** no `INFOPLIST_KEY_CKSharingSupported` (or `INFOPLIST_KEY_UIBackgroundModes`) build setting exists — unknown `INFOPLIST_KEY_*` names are silently ignored. Done instead with a partial `nomorewaste/Info.plist` holding both keys, merged into the generated plist via `INFOPLIST_FILE` alongside `GENERATE_INFOPLIST_FILE = YES`, plus a synchronized-group membership exception so the file is not also copied as a resource.
- [x] 11.3 Add a minimal `UIApplicationDelegateAdaptor` implementing `application(_:userDidAcceptCloudKitShareWith:)` to accept invitations — SwiftUI has no native hook for share acceptance.
- [x] 11.4 Create `nomorewaste/SharingController.swift` wrapping share creation for the `Household` object, participant lookup, stop-sharing, and leaving a shared household.
- [x] 11.5 Create `nomorewaste/HouseholdView.swift` with a `ShareLink` using `CKShareTransferRepresentation` to invite members, a member list marking the owner, and a sync status indicator. When the household has never been shared, show an invite prompt rather than an empty member list.
- [x] 11.6 Ensure a participant who accepts an invitation sees the shared household's list and inventory rather than their own local one, and that item writes land in the shared store.
- [x] 11.7 Implement the "one active household at a time" rule by pointing `activeHousehold` (3.8) at the shared household on accept and back at the personal one on leave — the fetches already scope to it, so no view should need changing.
- [x] 11.8 Confirm before leaving a household or stopping sharing, since neither is reversible from inside the app without a new invitation.
- [x] 11.9 When iCloud is unavailable, have the sharing entry point explain that sharing requires iCloud rather than failing silently or presenting an error.
- [x] 11.10 Add an unobtrusive sync-state indication for pending uploads that never blocks or interrupts the user.

## 12. Sharing verification — needs two iCloud accounts and two physical devices

- [x] 12.1 Invite a second iCloud account and accept the invitation; confirm the participant sees both the shopping list and the inventory.
- [x] 12.2 Confirm an item checked off by one member appears in the other member's inventory.
- [x] 12.3 Confirm the duplicate warning fires for a member against stock a *different* member checked off.
- [x] 12.4 Confirm inventory quantity edits by one member reach the other without a manual refresh.
- [x] 12.5 Exercise the concurrent-check-off case from the home-inventory spec; confirm the result is a possibly-low quantity that is directly correctable, and that nothing crashes or duplicates.
- [x] 12.6 Confirm undo refuses to overwrite a quantity another member changed, per 5.6.
- [x] 12.7 Confirm leaving a household and stopping sharing both behave sanely and leave each side with coherent data.
- [x] 12.8 Confirm a participant who had their own local items before joining still has them intact after leaving the shared household.
