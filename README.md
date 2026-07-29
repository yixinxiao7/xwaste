# xwaste

An iOS app with one purpose: **stop you from buying groceries you already have.**

## What

xwaste is a shopping list that doubles as a home inventory. Two tabs:

- **Shopping List** — add items, grouped automatically into store categories (Produce, Dairy & Eggs, …). Checking an item off doesn't delete it — it moves into your inventory.
- **At Home** — everything you own, in the same categories, with one-tap quantity steppers. Using the last onion removes the row.

The connective tissue is the warning: add something you already have at home and the app tells you — *"You already have 3 onions at home"* — while you type and again on save. It warns, never blocks; sometimes you really do need a fourth onion.

Households share one list and one inventory: invite a partner or roommate via iCloud and everyone shops against the same kitchen. No accounts, no sign-up — your iCloud identity is the identity.

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
