# xwaste

An app with one purpose: **stop you from buying groceries you already have.** Runs on iPhone and iPad, Apple Watch, and Mac.

## What

xwaste is a shopping list that doubles as a home inventory. Three tabs:

- **Shopping List** — add items, grouped automatically into store categories (Produce, Dairy & Eggs, …). Checking an item off doesn't delete it — it moves into your inventory.
- **At Home** — everything you own, in the same categories, with one-tap quantity steppers. Using the last onion removes the row.
- **Recipes** — a grid of your recipes, each marked with a check or an x for whether At Home covers every ingredient right now. Filter to what you can make or what's missing, tap a recipe to see which ingredient falls short, and add exactly the shortfall to the shopping list in one tap. **Start Cooking** opens an ingredient and step checklist; **Finish Cooking** subtracts what you used from At Home, with an undo that verifies nothing changed underneath it first.

The connective tissue is the warning: add something you already have at home and the app tells you — *"You already have 3 onions at home"* — while you type and again on save. It warns, never blocks; sometimes you really do need a fourth onion.

Households share one list and one inventory: invite a partner or roommate via iCloud and everyone shops against the same kitchen. No accounts, no sign-up — your iCloud identity is the identity.

**On the watch**, the same list is a remote for the shopping trip: two pages (list, then At Home), one tap on a row to check an item off, an undo screen right after, and a +/− screen for quantities. Adding, renaming, recategorizing, and sharing stay on the phone — so does the duplicate warning, since you cannot add from the wrist. The watch reads the household's live data over iCloud like any second device; without an iCloud account it says so rather than showing an empty list.

**On the Mac**, everything reachable by touch is reachable by pointer and keyboard: context menus carry every action iOS puts behind a swipe, the delete key removes the selected row, and ⌘N opens the add sheet with the name field focused.

## Why

Shopping lists are write-only: they say what you *want*, never what you *own*, so the buying decision happens without the one fact that would change it. The third onion goes soft because nobody remembered the first two. And since kitchens are shared, a solo inventory only solves half the problem — the person shopping is still buying blind against what their partner stocked. xwaste puts the "do I already have this?" answer at the exact moment of adding, for every member of the household.

## How

- **SwiftUI + Core Data with `NSPersistentCloudKitContainer`** — two stores (private + shared CloudKit database), offline-first: every operation works with no network or no iCloud account, and syncs when it can.
- **Sharing via `CKShare`** of a root `Household` entity that owns every item, so the list and inventory travel together as one unit. Chosen over SwiftData, which cannot share.
- **Categorization is a compiled-in keyword table** (~260 normalized terms) matched rightmost-first on word boundaries — "chocolate milk" is dairy, "milk chocolate" is a snack. Deterministic, instant, fully offline. **No AI, no ML, no network call** — by design, not by accident.
- **One item model, two locations.** Shopping list and inventory are the same record with a `location` field, so duplicate detection, check-off merging, and rename collisions are all resolved by one invariant: one row per normalized name per location.
- **Every destructive action has a way back.** Check-off shows an undo that *verifies before reversing* (it won't clobber a quantity another household member just changed), and any inventory item can be moved back to the list permanently.

## Development

Built spec-first with [OpenSpec](openspec/specs/) — six capability specs (49 requirements, 108 scenarios) are the contract; the archived change under `openspec/changes/archive/` holds the full design rationale and task log.

Requires Xcode 16+, iOS 18+, and a paid Apple Developer membership for the CloudKit entitlement. The bundle ID and CloudKit container intentionally keep the app's former name (`com.yixinxiao.nomorewaste`) — they are permanently bound server-side; see `CLAUDE.md`.
