> The watch target (group 1) is the first change requiring hand-written `project.pbxproj` surgery — synchronized groups do not cover new targets. Do it first and build all targets immediately; if hand-editing proves too brittle, the fallback is having the user add the target once via Xcode's GUI and diffing what it wrote.
> Groups 6–7 need the user's physical Apple Watch and MacBook (same iCloud account). They also close the deferred same-account sync check (old task 10.1 of `add-grocery-inventory`).

## 1. Watch target — project surgery

- [ ] 1.1 Add a single-target watchOS app target `xwaste-watch` to `project.pbxproj`: native target of type watch2-app (modern single-target watch app, no separate extension), product `xwaste-watch.app`, bundle ID `com.yixinxiao.nomorewaste.watchkitapp`, `WATCHOS_DEPLOYMENT_TARGET = 11.0`, `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.yixinxiao.nomorewaste` and `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES` (the watch is a CloudKit peer, not a phone accessory).
- [ ] 1.2 Create the `xwaste-watch/` folder as a `PBXFileSystemSynchronizedRootGroup` owned by the watch target, with a placeholder `XWasteWatchApp.swift` (`@main`) so the target builds from the start.
- [ ] 1.3 Share the non-UI files with the watch target via a membership exception set on the existing `xwaste/` group — `GroceryItem`, `Household`, `GroceryCategory`, `CategoryClassifier`, `GroceryStore`, `PersistenceController`, `XWaste.xcdatamodeld` — moving nothing on disk.
- [ ] 1.4 Create `xwaste-watch/xwaste-watch.entitlements`: the existing iCloud container `iCloud.com.yixinxiao.nomorewaste`, CloudKit service, `aps-environment` development. Set the watch target's `CODE_SIGN_ENTITLEMENTS`, `DEVELOPMENT_TEAM = P8L779MGGP`, automatic signing.
- [ ] 1.5 Embed the watch app in the iOS target (Embed Watch Content copy phase into `$(CONTENTS_FOLDER_PATH)/Watch`) and add the target dependency.
- [ ] 1.6 Confirm `xcodebuild` succeeds for all three destinations: iOS Simulator, watchOS Simulator, and macOS — before any watch UI is written.

## 2. macOS project configuration

- [ ] 2.1 Create `xwaste/xwaste-macOS.entitlements`: same iCloud container and CloudKit service, `com.apple.developer.aps-environment` (the macOS key differs from iOS), App Sandbox with `com.apple.security.network.client` for CloudKit traffic. Select it with `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` on the app target, leaving the iOS entitlements untouched.
- [ ] 2.2 Lower `MACOSX_DEPLOYMENT_TARGET` from 26.5.2 to 15.0 at the project level.
- [ ] 2.3 Confirm the Mac app builds, launches, and loads both stores on the user's MacBook with signing (not just `CODE_SIGNING_ALLOWED=NO` compile checks).

## 3. Watch UI

- [ ] 3.1 Build `XWasteWatchApp.swift` for real: `@main`, the shared `PersistenceController`, and a vertical page-style `TabView` — page one Shopping List, page two At Home — with the managed object context and active household injected as on iOS.
- [ ] 3.2 Build the watch shopping-list page: `@FetchRequest` scoped to `.shoppingList` and the active household, `CategorySection.sections(from:)` for grouping, fixed category order, empty categories hidden.
- [ ] 3.3 Build the watch row: item name and quantity, whole-row tap = check off via `GroceryStore.checkOff`, plus a distinct trailing quantity control that opens the 3.5 detail screen without triggering check-off.
- [ ] 3.4 Present the check-off result as a brief full-screen confirmation naming the item with an Undo button, ~5 s auto-dismiss, driven by the same `CheckOffUndo` value; wire Undo to `GroceryStore.undoCheckOff` including the changed-elsewhere message path. Leaving the screen dismisses it; expiry changes nothing.
- [ ] 3.5 Build the quantity detail screen: large +/− buttons calling `GroceryStore.adjustQuantity`; decrement to zero deletes the row and confirms with the same style of dismissible confirmation.
- [ ] 3.6 Build the At Home page with the same sectioning and the same quantity-adjustment path; no check-off affordance there.
- [ ] 3.7 Add the honest states: a "requires iCloud" screen when `CKContainer.accountStatus` is unavailable, and a syncing-in-progress empty state on cold first launch (empty store + account available), so an empty list never reads as an empty household. Verify no add, rename, category, delete, or sharing affordance exists anywhere on the watch.

## 4. Mac input parity (cross-platform edits to existing views)

- [ ] 4.1 Add context menus to shopping-list rows — Check Off, Edit, Delete — and inventory rows — Move to Shopping List, Edit, Delete — on all platforms (redundant with swipes on iOS by design; one view body, no forks).
- [ ] 4.2 Map the delete key to row deletion on macOS via `.onDeleteCommand` with list selection.
- [ ] 4.3 Add ⌘N (`.keyboardShortcut("n")`) to present the add-item sheet with the name field focused, on both screens.
- [ ] 4.4 Set the Mac window's `defaultSize` (~480×720) and a `minWidth`/`minHeight` on the root view at which tabs, toolbar, rows, and steppers all remain operable.
- [ ] 4.5 Re-verify iOS in the simulator after 4.1–4.3: swipes still work, context menus present but not disruptive, no behavior drift.

## 5. Simulator verification (no hardware)

- [ ] 5.1 Watch simulator: both pages render, category sections and fixed order correct, rows tap to check off, quantity screen adjusts and deletes at zero.
- [ ] 5.2 Watch simulator: the no-iCloud screen appears when unprovisioned, and the syncing empty state appears (not "Nothing to buy") on a cold signed-in launch.
- [ ] 5.3 Mac: walk the group-9 scenarios that are input-idiom-sensitive — delete via context menu and delete key, move-back via context menu, ⌘N add, duplicate warning inline note + alert with Cancel preserving values, undo banner behavior.
- [ ] 5.4 Mac: shrink the window to minimum and confirm nothing clips or becomes unreachable.
- [ ] 5.5 Run `openspec validate add-watchos-macos --strict` and resolve findings.

## 6. Physical-watch verification — needs the paired Apple Watch

- [ ] 6.1 Install on the physical watch via Xcode; confirm the household's list appears after first sync (cold-launch state resolves to data).
- [ ] 6.2 Check off an item on the watch; confirm it lands in At Home on the watch, the iPhone, and (if the shared household is active) the second tester's phone.
- [ ] 6.3 Undo a watch check-off within the window; confirm exact reversal. Then race it: edit the home quantity from the iPhone between watch check-off and watch undo; confirm the changed-elsewhere path (list restored, home untouched, message shown).
- [ ] 6.4 Adjust a quantity to zero on the watch; confirm the row disappears everywhere and no zero row exists.
- [ ] 6.5 Add an item on the iPhone; confirm it reaches the wrist without touching the watch.

## 7. Same-account convergence — closes deferred 10.1

- [ ] 7.1 With Mac and iPhone on the same iCloud account: add on the Mac → appears on iPhone; edit quantity on iPhone → appears on Mac; check off on one → inventory updates on the other. No manual refresh anywhere.
- [ ] 7.2 Take the iPhone offline, make changes on both it and the Mac, reconnect; confirm both converge with nothing lost (the last-writer-wins quantity caveat applies as specced).
- [ ] 7.3 Record in the archived `add-grocery-inventory` tasks file (archive note, not a checkbox flip) that deferred 10.1 is now covered by this change's 7.1–7.2.

## 8. Docs

- [ ] 8.1 Update README (platform list: iPhone/iPad, Apple Watch, Mac; watch scope note) and CLAUDE.md's current-state section.
- [ ] 8.2 Update `.wolf/anatomy.md` with the `xwaste-watch/` folder and new entitlements files; log learnings from the pbxproj target surgery to `.wolf/cerebrum.md`.
