## Why

The moment the app exists to serve — "do I already have this?" — happens in two places the iPhone build underserves: in the store with hands full (where a wrist glance and a wrist tap beat pulling out a phone) and in the kitchen at a desk (where the household's Mac is already open). The app already *launches* on macOS as an unpolished side effect of `SUPPORTED_PLATFORMS`, but nothing about it is designed, verified, or honest about platform conventions; watchOS is not supported at all. This change makes both first-class.

## What Changes

- Add a **watchOS app** (new Xcode target) focused on the shopping trip: view the list in category sections, check items off with a single tap (with undo), adjust quantities, and glance at the At Home inventory. **Deliberately excluded from the watch:** adding, renaming, recategorizing, sharing management, and therefore the duplicate-warning UI — those remain phone flows. The watch is a remote for the list, not a second editor.
- Watch data arrives via the same `NSPersistentCloudKitContainer` mirroring (private + shared databases) against the existing container. A watch signed into the household's iCloud account sees the same active household, including a shared one. **Without iCloud, the watch app shows an honest "requires iCloud" state** — there is no local-only watch mode (no WatchConnectivity phone-mirroring in v1).
- Promote **macOS from "compiles" to supported**: proper Mac idioms for every destructive or row-level action (context menus and the delete key replace swipe gestures, which do not exist on the Mac), keyboard shortcut for add, sensible default/minimum window size, verified sharing entry point, and a macOS-correct entitlements setup (the push and sandbox entitlement keys differ from iOS).
- Lower `MACOSX_DEPLOYMENT_TARGET` from the beta default (26.5.2) to a released version aligned with the iOS 18 generation.
- Same-account sync between iPhone and a second device becomes verifiable for the first time (the deferred task 10.1 from `add-grocery-inventory`): the user's physical Apple Watch and Mac are both second devices on the same iCloud account.
- No behavior changes on iOS/iPadOS. visionOS remains build-only, unchanged.

## Capabilities

### New Capabilities

- `watch-app`: What the watchOS app shows and does — the check-off-focused scope, its undo affordance, quantity adjustment, the At Home glance, sync expectations, and the no-iCloud state.
- `mac-experience`: Platform-idiom requirements for the macOS app — input methods for every action that is gesture-based on iOS, keyboard access, window behavior, and parity of the shared-household features.

### Modified Capabilities

<!-- None. The existing six capability specs are written platform-neutrally ("the system SHALL...") and their requirements do not change; the new specs bind those behaviors to two new platforms' interaction idioms. -->

## Impact

- **Xcode project**: a new watchOS app target — the first change that genuinely requires `project.pbxproj` surgery (synchronized file groups do not cover new targets). New shared `xwaste/Shared` grouping is *not* needed: model, store, and classifier files are UI-free and join the watch target by membership. New watch entitlements file; per-platform entitlements handling for macOS (`com.apple.developer.aps-environment` vs `aps-environment`, sandbox network-client).
- **Code**: watch UI views (list, row, undo, inventory glance, no-iCloud state) in a new `xwaste-watch/` folder. Small cross-platform adjustments in existing views (context menus added alongside swipe actions — additive on iOS). `PersistenceController`, `GroceryStore`, `CategoryClassifier`, and the Core Data model are reused unmodified on both platforms.
- **App Store Connect / TestFlight**: the watch app rides inside the existing iOS app record; the Mac app can be offered from the same record. CloudKit container, bundle ID root, and production schema are unchanged — no new server-side resources.
- **Verification hardware**: user's physical Apple Watch (paired, same iCloud account) and MacBook. Closing the deferred same-account sync check (old task 10.1) becomes part of this change's verification.
- **Docs**: README platform list, CLAUDE.md current-state note.
