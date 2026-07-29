## Why

People buy groceries they already have at home, and the surplus rots — the third onion goes soft because nobody remembered the first two. Existing shopping lists are write-only: they tell you what you want to buy but never what you already own, so the buying decision happens without the one fact that would change it. This change turns the list into a live inventory so the answer to "do I need this?" is visible at the moment of adding.

Waste is also a household problem, not an individual one. If one person tracks the kitchen and the other does the shopping, the tracking is worthless — the shopper is still buying blind. So the inventory has to be shared with the people who shop for the same kitchen, or it only solves half the problem.

## What Changes

- Add a persistent grocery item store: name, whole-number quantity, category, and location (on the shopping list vs. at home). Items survive app restarts.
- Add a **Shopping List** screen that groups items into sections by category, mirroring the iOS Reminders grocery list. Add, edit, and delete items inline.
- Automatically assign a category on add and on rename using a **built-in keyword dictionary** — a static, offline lookup table. **No AI, no network calls, no model inference.** Unmatched items fall into an "Other" section, and the user can override any assignment manually.
- Checking off a shopping-list item marks it purchased: it leaves the list and its quantity is added to the home inventory.
- Show an **Undo** affordance immediately after check-off that fully reverses the move (quantity and section restored). The reverse move is also available permanently from the inventory, so a missed toast is never a dead end.
- Add a **Home Inventory** screen showing everything currently at home, grouped by the same categories, with direct quantity editing and deletion. Setting a quantity to zero removes the item from the inventory.
- Warn — but do not block — when the user adds an item they already have at home. The warning states the quantity on hand ("You already have 3 onions at home") and offers to add anyway or cancel.
- **Sync all data across the user's own devices via iCloud**, offline-first: the app is fully usable with no connection and reconciles when one returns.
- **Let a user share their household with other iCloud users**, so partners and roommates see one shopping list and one inventory. Both the list and the inventory are shared as a single unit — sharing only the list would leave invited members comparing it against their own empty inventory, breaking the duplicate warning for them. Participants have read-write access; the iCloud account is the identity, so there is no sign-up, password, or account screen.
- Replace the placeholder `ContentView` with a two-tab app shell (Shopping List / At Home).

Non-goals for this change: expiration dates, freshness estimates, notifications, recipes, barcode scanning, any AI-assisted categorization, non-Apple platforms (the iCloud-as-identity choice rules out Android and web permanently), per-member permissions beyond read-write, and belonging to more than one shared household at a time (a user has their personal household plus at most one joined household; accepting a second invitation while already in one is undefined here).

## Capabilities

### New Capabilities

- `grocery-items`: The shared item model and persistence layer — name, whole-number quantity, category, and list-vs-home location — plus create, edit, delete, and name-normalization rules used by every other capability.
- `item-categorization`: Deterministic, offline assignment of a grocery category from an item's name via a built-in keyword dictionary, with an "Other" fallback and a persistent manual override.
- `shopping-list`: The shopping list screen — category-sectioned display, add/edit/delete, check-off to mark an item purchased, and the undo affordance that reverses a check-off.
- `home-inventory`: The at-home inventory screen — category-sectioned display of owned items, quantity adjustment, removal, and moving an item back onto the shopping list.
- `duplicate-warning`: The non-blocking alert shown when a user adds a shopping-list item that already has a nonzero quantity at home, including the on-hand count and the add-anyway / cancel choice.
- `household-sharing`: iCloud sync of all item data across a user's devices, plus inviting other iCloud users into a shared household, accepting an invitation, seeing members, leaving or removing access, and the conflict and offline behavior that sharing implies.

### Modified Capabilities

None — this is the first change in the project; `openspec/specs/` is empty.

## Impact

- **Code**: `nomorewaste/ContentView.swift` is currently a placeholder holding both `@main` and the root view; it will be split into an app entry point, a Core Data stack, two tab screens, item add/edit views, a category dictionary, and sharing UI. Expect the single-file app to become a small multi-file SwiftUI target.
- **Xcode project**: New Swift files are picked up automatically by the existing file-system-synchronized group, so no `project.pbxproj` edits are needed to add sources. The project does need the **iCloud capability with CloudKit enabled**, a CloudKit container identifier, remote-notification background mode, and `CKSharingSupported` set in the Info.plist.
- **Deployment target**: lowered from iOS 27.0 to **iOS 18.0**. The current setting would restrict installs to devices on the newest OS for no benefit; the CloudKit sharing APIs this change relies on have been available since iOS 15.
- **Apple Developer Program**: CloudKit requires a paid membership — free personal-team provisioning cannot grant the iCloud entitlement. The membership for this project was approved on 2026-07-21, so the entitlement, the CloudKit container, and the remote-notification background mode are configured before any feature code is written, and sync is on throughout development.
- **Dependencies**: None added. Persistence uses Core Data and CloudKit from the system SDK; categorization uses a hardcoded table compiled into the app.
- **Privacy**: Item data leaves the device and is stored in the user's iCloud account. Shared records count against the household owner's iCloud quota, not each participant's. Users with no iCloud account or with iCloud Drive disabled must still get a fully working local-only app.
- **Data**: Introduces the app's first persistent store. No migration concerns — there is no existing data — but records must live in a CloudKit-shareable zone from the first release, since relocating them after users have data is a migration.
- **Users**: The placeholder "Hello, world!" screen is removed; this is the app's first real UI.
