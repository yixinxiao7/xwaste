> The watch target (group 1) is the first change requiring hand-written `project.pbxproj` surgery — synchronized groups do not cover new targets. Do it first and build all targets immediately; if hand-editing proves too brittle, the fallback is having the user add the target once via Xcode's GUI and diffing what it wrote. The test targets (group 3) are also new targets, but lower-risk: they don't ship.
> Verification is automation-first. Groups 1–7 involved no human and are complete. **Group 8 was skipped** (2026-08-05, user decision — no non-ADP Apple ID available; see its note). Group 9 is therefore the only pass that touches CloudKit at all: its store-logic items re-confirm groups 4/7, but its *sync* items are first-time verification, and it still closes the deferred same-account sync check (old task 10.1 of `add-grocery-inventory`).

## 1. Watch target — project surgery

- [x] 1.1 Add a single-target watchOS app target `xwaste-watch` to `project.pbxproj`: native target of type watch2-app (modern single-target watch app, no separate extension), product `xwaste-watch.app`, bundle ID `com.yixinxiao.nomorewaste.watchkitapp`, `WATCHOS_DEPLOYMENT_TARGET = 11.0`, `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.yixinxiao.nomorewaste` and `INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES` (the watch is a CloudKit peer, not a phone accessory).
- [x] 1.2 Create the `xwaste-watch/` folder as a `PBXFileSystemSynchronizedRootGroup` owned by the watch target, with a placeholder `XWasteWatchApp.swift` (`@main`) so the target builds from the start.
- [x] 1.3 Share the non-UI files with the watch target via a membership exception set on the existing `xwaste/` group — `GroceryItem`, `Household`, `GroceryCategory`, `CategoryClassifier`, `GroceryStore`, `PersistenceController`, `XWaste.xcdatamodeld` — moving nothing on disk.
- [x] 1.4 Create `xwaste-watch/xwaste-watch.entitlements`: the existing iCloud container `iCloud.com.yixinxiao.nomorewaste`, CloudKit service, `aps-environment` development. Set the watch target's `CODE_SIGN_ENTITLEMENTS`, `DEVELOPMENT_TEAM = P8L779MGGP`, automatic signing.
- [x] 1.5 Embed the watch app in the iOS target (Embed Watch Content copy phase into `$(CONTENTS_FOLDER_PATH)/Watch`) and add the target dependency.
- [x] 1.6 Confirm `xcodebuild` succeeds for all three destinations: iOS Simulator, watchOS Simulator, and macOS — before any watch UI is written.

## 2. macOS project configuration

- [x] 2.1 Create `xwaste/xwaste-macOS.entitlements`: same iCloud container and CloudKit service, `com.apple.developer.aps-environment` (the macOS key differs from iOS), App Sandbox with `com.apple.security.network.client` for CloudKit traffic. Select it with `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` on the app target, leaving the iOS entitlements untouched.
- [x] 2.2 Lower `MACOSX_DEPLOYMENT_TARGET` from 26.5.2 to 15.0 at the project level.
- [x] 2.3 Confirm the Mac app builds, launches, and loads both stores on this Mac with signing (not just `CODE_SIGNING_ALLOWED=NO` compile checks).

## 3. Test infrastructure — the app's first test targets

- [x] 3.1 Add a `xwasteTests` unit-test target to `project.pbxproj`, hosted by the iOS app (`TEST_HOST`, `@testable import xwaste`), running on the iOS simulator.
- [x] 3.2 Ensure `PersistenceController` offers an in-memory store variant for tests (add one if the preview support from v1 doesn't already provide it).
- [x] 3.3 Add a `xwaste-watchUITests` XCUITest target against the watch app, running on the watchOS simulator.
- [x] 3.4 Confirm `xcodebuild test` runs green with a placeholder test in each target, on the iOS simulator and the watch simulator.
- [x] 3.5 Scope note, **revised during implementation**: the original note ruled out iOS/macOS UI-test targets because "iOS and the Mac are directly drivable by the agent". That premise proved false for iOS on this machine: the Xcode 27 beta ships no `Simulator.app`, and the desktop simulator panel is disabled for this account by a rollout flag. A third target, `xwasteUITests`, therefore carries 7.5 headlessly (user-approved 2026-07-29). *Later correction (2026-08-05):* a simulator GUI **was** obtained — stable Xcode 26.6's `Simulator.app` works once the CoreSimulator service is restarted under it (no `sudo`). The extra target is kept anyway: headless XCUITest is more reliable and re-runnable than pixel-driving a GUI, and it now guards iOS permanently. **macOS keeps the original treatment** — the Mac app is an ordinary Mac app the agent can drive directly, so 7.6/7.7 stay driven checks with no macOS UI-test suite.

## 4. Store-logic unit tests — the invariants, before any new UI

> These absorb the logic halves of what the previous plan deferred to a physical watch (old 6.3/6.4). They are deterministic in-memory Core Data operations: no CloudKit, no devices, no flakiness. They also become the app's permanent regression guard for its stated non-negotiables (undo path, no zero rows, warn-never-block).

- [x] 4.1 `checkOff`: item leaves the list; quantity merges into an existing home row or creates one; the returned `CheckOffUndo` captures prior state.
- [x] 4.2 `undoCheckOff` happy path: exact reversal within the window — list row restored with original quantity, home row back to prior state (including removal of a home row the check-off created).
- [x] 4.3 `undoCheckOff` changed-elsewhere race: mutate the affected home item between check-off and undo; assert the list row is restored, the home item is left as the other writer set it, and the changed-elsewhere result is reported.
- [x] 4.4 Undo expiry / abandonment: after the window lapses or the undo value is discarded, nothing further changes.
- [x] 4.5 `adjustQuantity`: increment and decrement across both locations; decrement to zero deletes the row; no zero-quantity row can exist afterward.
- [x] 4.6 Move to Shopping List: home row returns to the list, merging into an existing list row when the normalized name matches.
- [x] 4.7 Duplicate detection: normalized-name matching reports an existing item (the warn-path input), and never blocks the add.

## 5. Watch UI

- [x] 5.1 Build `XWasteWatchApp.swift` for real: `@main`, the shared `PersistenceController`, and a vertical page-style `TabView` — page one Shopping List, page two At Home — with the managed object context and active household injected as on iOS.
- [x] 5.2 Build the watch shopping-list page: `@FetchRequest` scoped to `.shoppingList` and the active household, `CategorySection.sections(from:)` for grouping, fixed category order, empty categories hidden.
- [x] 5.3 Build the watch row: item name and quantity, whole-row tap = check off via `GroceryStore.checkOff`, plus a distinct trailing quantity control that opens the 5.5 detail screen without triggering check-off.
- [x] 5.4 Present the check-off result as a brief full-screen confirmation naming the item with an Undo button, ~5 s auto-dismiss, driven by the same `CheckOffUndo` value; wire Undo to `GroceryStore.undoCheckOff` including the changed-elsewhere message path. Leaving the screen dismisses it; expiry changes nothing.
- [x] 5.5 Build the quantity detail screen: large +/− buttons calling `GroceryStore.adjustQuantity`; decrement to zero deletes the row and confirms with the same style of dismissible confirmation.
- [x] 5.6 Build the At Home page with the same sectioning and the same quantity-adjustment path; no check-off affordance there.
- [x] 5.7 Add the honest states: a "requires iCloud" screen when `CKContainer.accountStatus` is unavailable — triggered by `.noAccount` *and* `.temporarilyUnavailable` (the latter is what an Advanced-Data-Protection account yields on simulators) — and a syncing-in-progress empty state on cold first launch (empty store + account available), so an empty list never reads as an empty household. No add, rename, category, delete, or sharing affordance exists anywhere on the watch.

## 6. Mac input parity (cross-platform edits to existing views)

- [x] 6.1 Add context menus to shopping-list rows — Check Off, Edit, Delete — and inventory rows — Move to Shopping List, Edit, Delete — on all platforms (redundant with swipes on iOS by design; one view body, no forks).
- [x] 6.2 Map the delete key to row deletion on macOS via `.onDeleteCommand` with list selection.
- [x] 6.3 Add ⌘N (`.keyboardShortcut("n")`) to present the add-item sheet with the name field focused, on both screens.
- [x] 6.4 Set the Mac window's `defaultSize` (~480×720) and a `minWidth`/`minHeight` on the root view at which tabs, toolbar, rows, and steppers all remain operable.

## 7. Automated verification — simulator and code only, no human

- [x] 7.1 Watch XCUITest suite (smoke level, per the group-3 scope note): both pages reachable, category sections in fixed order with empty categories hidden, row tap → confirmation naming the item with Undo, Undo restores the row, quantity screen adjusts, decrement-to-zero removes the row.
- [x] 7.2 Watch XCUITest honest states: signed-out simulator shows the requires-iCloud screen (`.noAccount`); assert the same screen for `.temporarilyUnavailable`; cold signed-in launch shows the syncing state, never "Nothing to buy".
- [x] 7.3 Watch XCUITest absence assertions: no add, rename, recategorize, share, or non-decrement delete affordance exists on any watch screen.
- [x] 7.4 Watch visual QC: `xcrun simctl io <udid> screenshot` of each screen, reviewed in-session (the Claude Desktop simulator panel is iOS-only and cannot attach to watch simulators — screenshots are the visual path).
- [x] 7.5 iOS regression drive on the simulator after group 6: swipes still work, context menus present but not disruptive, add/duplicate-warning flow unchanged. One-time check, not a recurring suite — the same view bodies now serve two platforms.
- [x] 7.6 Mac driven checks (agent drives the launched Mac app): delete via context menu and delete key, Move to Shopping List via context menu, ⌘N opens the add sheet with name focused, duplicate warning inline note + alert with Cancel preserving typed values, undo banner behavior.
- [x] 7.7 Mac window: shrink to minimum; nothing clips or becomes unreachable.
- [x] 7.8 Run `openspec validate add-watchos-macos --strict` and resolve findings.

## 8. Simulator CloudKit probe — the single human step before hardware (~2 min, no hardware)

> **NOT PERFORMED — user decision, 2026-08-05.** The whole group depends on a non-ADP Apple ID being signed into the simulators, and no such account is available: the only Apple ID on hand (`appleyixinxiao7@gmail.com`) is the user's personal one, which has Advanced Data Protection and therefore reproduces the very dead end this group exists to escape. Rather than create an account solely for a de-risking step, the user chose to go straight to hardware. The simulator GUI itself was *not* the blocker — it was made to work (see the note in group 9).
>
> Original rationale, kept for the record: the user's own account cannot do this: Advanced Data Protection keeps simulator CloudKit at `.temporarilyUnavailable`. The non-ADP test Apple ID (already required as the second account for sharing verification) unblocks it. Apple-Silicon simulators can receive sandbox APNs, so sync on simulators is a live question to answer, not a known dead end.

- [ ] 8.1 User signs the non-ADP test Apple ID into the iOS simulator and, if willing, the Mac (the agent cannot enter credentials; this is the entire human involvement in this group).
- [ ] 8.2 Probe Mac ↔ iOS-simulator convergence: add, edit-quantity, and check-off propagate in both directions; record whether import is automatic (push-driven) or needs an app foreground/relaunch nudge.
- [ ] 8.3 Offline/reconnect merge rehearsal on the same pair: changes on both sides while one is offline converge after reconnect with nothing lost (last-writer-wins quantity caveat as specced).
- [ ] 8.4 Watch-simulator account probe: determine whether the watch simulator can reach the test account's data at all; record the outcome either way (this replaces the prior plan's untested assumption that watch-sim CloudKit is unusable).
- [ ] 8.5 Mark which sync behaviors group 8 proved; group 9 re-confirms only the remainder plus what genuinely requires physical devices. **Resolved by the group-8 skip: group 8 proved nothing, so group 9 carries the entire sync burden.**

## 9. Hardware confirmation — physical watch + iPhone + Mac, final pass

> **Scope widened because group 8 was skipped.** The store logic below still re-confirms automated results (groups 4 and 7), but every *sync* item — 9.1, 9.4, 9.5, 9.6 — is now **first-time verification, not re-confirmation**: no CloudKit convergence has been exercised anywhere yet, on any platform. Treat a failure here as a live question, not a provisioning smell. The changed-elsewhere undo race is still deliberately *not* reproduced on hardware — its logic is proven by 4.3, and staging a multi-device race by hand is flaky by design.
>
> Also worth knowing before starting: both macOS defects found in group 7 were **pre-existing since v1**, which means the Mac build had never been run by anyone until 2026-08-05. 9.5/9.6 are that build's first real-world exercise.

- [x] 9.1 Install on the physical watch ~~via Xcode~~ **via TestFlight** (2026-09-09); confirm the household's list appears after first sync (cold-launch state resolves to data). **Route changed:** the Xcode/dev-install path was unreachable — the watch never enrolled with Xcode (invisible to `devicectl`/`xctrace`/Devices window), so Developer Mode could not be enabled and the watch was not a registered development device. A distribution-signed TestFlight build needs neither. **Verified only after fixing bug-049** (fresh install pinned a self-invented empty household, so the watch showed "Nothing to buy" while the data sat unreachable in its own store).
- [x] 9.2 Check off an item on the watch; confirm it lands in At Home on the watch, the iPhone, and (if the shared household is active) the second tester's phone. Undo one on-wrist check-off within the window; confirm exact reversal.
- [x] 9.3 Adjust a quantity to zero on the watch; confirm the row disappears everywhere and no zero row exists.
- [x] 9.4 Add an item on the iPhone; confirm it reaches the wrist without touching the watch.
- [x] 9.5 With Mac and iPhone on the same iCloud account: add on the Mac → appears on iPhone; edit quantity on iPhone → appears on Mac; check off on one → inventory updates on the other. No manual refresh anywhere (silent-push delivery on real devices is the part group 8 cannot prove).
- [x] 9.6 Take the iPhone offline, make changes on both it and the Mac, reconnect; confirm both converge with nothing lost.
- [x] 9.7 Record in the archived `add-grocery-inventory` tasks file (archive note, not a checkbox flip) that deferred 10.1 is now covered by 9.5–9.6. **Done 2026-09-09.** Note also records that 9.2/9.4 covered watch↔iPhone, and that the check found bug-049 rather than merely confirming existing behaviour.

## 10. Docs

- [x] 10.1 Update README (platform list: iPhone/iPad, Apple Watch, Mac; watch scope note) and CLAUDE.md's current-state section — including that the project now has test targets.
- [x] 10.2 Update `.wolf/anatomy.md` with the `xwaste-watch/` folder, test-target folders, and new entitlements files; log learnings from the pbxproj target surgery and the group-8 probe outcome to `.wolf/cerebrum.md`.
