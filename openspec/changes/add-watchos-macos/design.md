## Context

v1 shipped as an iPhone-designed app that also compiles for macOS and visionOS. The layers below the UI — `GroceryItem`/`Household` model, `GroceryStore` mutations, `CategoryClassifier`, `PersistenceController` — are already platform-clean: pure Swift over Core Data with no UIKit dependency (the sole UIKit code, share acceptance, is `#if os(iOS)`-guarded). The UI layer is SwiftUI throughout and mostly cross-platform, with prior macOS-availability fixes already in place (`.navigation` toolbar placement, `toolbarTitleDisplayMode`, guarded `textInputAutocapitalization`).

Known constraints, from the codebase and prior sessions:

- **New targets require real `project.pbxproj` editing.** The synchronized file group auto-includes files in `xwaste/` for the existing target only. This is the first change that adds a target.
- **CloudKit container, bundle ID, and store filenames are fixed** (`iCloud.com.yixinxiao.nomorewaste`, `com.yixinxiao.nomorewaste`, `NoMoreWaste*.sqlite`) — the rename decision binds them permanently. Watch and Mac must attach to these, not introduce new ones.
- **Entitlement keys differ by platform**: iOS uses `aps-environment`; macOS uses `com.apple.developer.aps-environment` and additionally needs `com.apple.security.network.client` under the App Sandbox for CloudKit traffic. One shared entitlements file cannot serve both correctly.
- **The user has a paired physical Apple Watch and a MacBook on the same iCloud account** — both watch verification and the previously-deferred same-account sync check (old task 10.1) are unblocked.
- User preference, consistently expressed: simplicity over feature count; warnings never block; destructive actions get an undo path.

## Goals / Non-Goals

**Goals:**

- A watch app that makes the *shopping trip* phone-free: glance the list, check off, adjust quantity, glance the inventory — against the household's live shared data.
- macOS as a supported platform: every action reachable by mouse and keyboard, no iOS-gesture-only dead ends, correct entitlements, verified sharing.
- Zero divergence in business logic: both platforms consume `GroceryStore` and the existing model unchanged; the invariant set (one row per normalized name per location, no zero quantities, undo-verifies-before-reversing) holds identically everywhere.
- Close the deferred same-account sync verification using the watch and Mac as second devices.

**Non-Goals:**

- Adding, renaming, or recategorizing items **on the watch** — and consequently any duplicate-warning UI there. The phone is the editor; the watch is a remote.
- WatchConnectivity phone-mirroring for non-iCloud users. The watch without iCloud gets an honest empty state, not a second sync stack. (Same accepted ceiling as iCloud-as-identity itself.)
- Watch complications, widgets, Live Activities, App Intents/Siri.
- visionOS work of any kind; iPad-specific layout work (iPad keeps the iPhone layout, as today).
- Mac-specific re-architecture (NavigationSplitView sidebars, multiple windows, menu-bar extras). The two-tab structure stays; this change makes it *correct* on the Mac, not *native-maximal*.

## Decisions

### The watch is a CloudKit peer, not a phone accessory

The watch app runs its own `NSPersistentCloudKitContainer` against the same container and store descriptions (private + shared scope), exactly like a second iPhone. Data reaches it via CloudKit mirroring, not via the paired phone.

*Why not WatchConnectivity mirroring:* it is a second, hand-rolled sync protocol with its own conflict story — the exact machinery `NSPersistentCloudKitContainer` exists to avoid. The cost is that a watch with no iCloud shows nothing; that is the app's existing identity ceiling, stated honestly on-screen. The win is that shared households work on the watch for free, because the shared-store mirroring and `activeHousehold` resolution are the same code.

*Consequence:* `PersistenceController`, including the legacy `NoMoreWaste*.sqlite` filenames (which are per-device paths, so the watch's fresh install simply creates its own files with those names), compiles into the watch target unchanged. The `#if DEBUG` schema-push helper stays iOS-only in practice by never being invoked from watch code.

### Check-off on the watch reuses `CheckOffUndo`, surfaced as a full-screen confirmation with Undo

Tapping a row calls the same `GroceryStore.checkOff`, and the watch keeps the returned `CheckOffUndo` in view state exactly as `ShoppingListView` does, with the same ~5-second window and the same verify-before-reverse path (a shared household member can race the watch too). The affordance is a brief full-screen confirmation ("Checked off Broccoli — Undo") rather than an iOS-style bottom banner, because on a 40 mm screen an overlay banner *is* the screen. Same rules: expiry changes nothing, leaving the screen dismisses it, move-back-on-the-phone is the permanent recovery.

### Quantity on the watch: +/- buttons on a detail screen, not steppers in rows

watchOS has no `Stepper`, and cramming tap targets into list rows invites accidental check-offs. Row tap = check off (the primary action must be the cheapest); a quantity tap target on the row's trailing edge opens a minimal detail screen with large +/− buttons. Decrement-to-zero deletes, same as everywhere — with the existing confirmation-free semantics, because the row is recoverable from the phone and the watch shows the same undo-style confirmation after deletion-by-decrement.

### Watch information architecture: two pages, list first

A vertical `TabView` (page style): page one Shopping List, page two At Home (read-and-adjust glance). Matches the phone's two-destination model and the "list is the default screen" requirement without introducing watch navigation chrome.

### macOS input parity via context menus + delete key, added cross-platform

Every row action that is swipe-only on iOS gains a context menu (right-click on Mac, long-press on iOS): Delete, Move to Shopping List / check-off equivalents, Edit. `.onDeleteCommand` maps the delete key to row deletion on the Mac. Context menus are *added on all platforms* rather than `#if`-forked — on iOS they are a redundant affordance, which is cheaper to maintain than two diverging view bodies. ⌘N presents the add sheet via `.keyboardShortcut`. Swipe actions remain for iOS.

### Per-platform entitlements files, one target

The iOS entitlements file stays as-is. macOS gets its own `xwaste-macOS.entitlements` (same iCloud container; `com.apple.developer.aps-environment`; App Sandbox with `com.apple.security.network.client`) selected via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`. The watch target gets `xwaste-watch.entitlements` (iCloud container + CloudKit, aps-environment). This keeps each platform's signed capabilities reviewable in one file each, rather than one file with cross-platform key soup.

### Watch target layout: `xwaste-watch/` folder, shared files by target membership

The watch app's views live in a new `xwaste-watch/` synchronized folder owned by the watch target. The shared non-UI files (`GroceryItem`, `Household`, `GroceryCategory`, `CategoryClassifier`, `GroceryStore`, `PersistenceController`, `XWaste.xcdatamodeld`) are added to the watch target via a membership exception set on the existing `xwaste/` synchronized group — no file moves, no new "Shared" directory, no risk to the existing target's membership. The watch app is a single-target watchOS app (modern style, no separate extension target).

*Why not move shared files into a `Shared/` folder:* pure churn — every path in anatomy/docs changes, git history fragments, and synchronized-group membership exceptions express the same thing without moving anything.

### Mac window: default and minimum size, nothing fancier

`defaultSize` around 480×720 with a sensible `minWidth`/`minHeight` on the root view, so the two-tab layout cannot be squashed into uselessness. No scene re-architecture.

## Risks / Trade-offs

- **The pbxproj watch-target surgery is hand-written, not Xcode-generated** → highest-risk step; mitigated by doing it first, building all targets immediately, and keeping the diff reviewable. If hand-editing proves too brittle, fallback is asking the user to add the target via Xcode's GUI once and diffing what it wrote.
- **CloudKit-only watch means a cold first launch** (empty until first import completes) → acceptable; show a syncing indicator in the empty state so it reads as "loading", not "broken". Real risk only when the watch has no iCloud, which gets the honest message instead.
- **Watch storage of full history + two stores is heavier than typical watch apps** → dataset is text rows in the low hundreds; negligible in practice.
- **watchOS simulator CloudKit is unreliable** → all sync-dependent watch verification runs on the physical watch; the simulator verifies layout and no-iCloud states only.
- **macOS TestFlight/notarization is a distinct distribution surface** → out of scope for verification here beyond local Xcode runs on the user's Mac; Mac App Store distribution is a later decision.
- **Context menus on iOS duplicate swipe actions** → mild redundancy accepted to keep one view body per screen.
