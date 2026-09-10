# xwaste

An iOS SwiftUI app whose single purpose is **reducing food waste**: the shopping list doubles as a home inventory, so "do I already have onions?" is answerable at the moment of adding.

**Naming:** the app was renamed from `nomorewaste` to `xwaste` on 2026-07-28. The bundle ID (`com.yixinxiao.nomorewaste`), the CloudKit container (`iCloud.com.yixinxiao.nomorewaste`), and the on-disk store filenames (`NoMoreWaste.sqlite`, `NoMoreWaste-shared.sqlite`) deliberately keep the old name — they are bound to the App Store Connect record, a permanent CloudKit container, and existing installs' data. Do not "fix" them.

## Current state

v1 is implemented, verified, and on TestFlight. The `add-grocery-inventory` change is archived at `openspec/changes/archive/2026-07-28-add-grocery-inventory/` (proposal, design, 97-task log). Its one deferred check — same-account two-device sync (task 10.1) — was **closed 2026-09-09** by `add-watchos-macos` 9.5–9.6.

`add-watchos-macos` is **49/54 complete**: watchOS app, first-class macOS support, three test targets, and the full hardware pass are done. The only outstanding items are group 8 (simulator CloudKit probe), **skipped by user decision** for want of a non-ADP Apple ID.

**Hardware-only defects this change surfaced** — none reproducible on a simulator:
- `bug-049` — a fresh install on a *second* device invented its own empty household and never adopted the synced one, so it showed an empty list forever. Latent since v1.
- `bug-046/047` — macOS `List` mis-diffs row removal in a multi-section list; `.frame(minWidth:)` silently overrode `.defaultSize`. Both pre-existing since v1, invisible until the Mac build was actually run.
- `bug-048` — watchOS refuses to install an app whose icon set it can't satisfy; a single 1024 icon is **not** expanded for the watch idiom, unlike iOS.

**Distribution note:** the watch app could not be installed via Xcode (the watch never enrolled for development), so it reaches hardware through **TestFlight**. Dev-signed builds use the CloudKit *development* database and TestFlight builds use *production* — two devices only sync if signed the same way.

## Targets and tests

Five targets: `xwaste` (iPhone/iPad/Mac/visionOS), `xwaste-watch` (watchOS, embedded in the iOS app), and the project's first test targets — `xwasteTests` (Swift Testing over an in-memory Core Data stack), `xwasteUITests` (XCUITest on the iOS simulator), and `xwaste-watchUITests` (XCUITest on the watch simulator).

Both UI suites drive `LaunchSupport` seams via launch environment (all `#if DEBUG`): `XWASTE_UITEST_SEED=1` swaps in a seeded in-memory stack (`0` = empty), `XWASTE_ACCOUNT_STATUS` pins `CKAccountStatus`, `XWASTE_CONFIRMATION_SECONDS` widens the undo window so slow simulators don't flake. The Mac app accepts them too — launch its binary directly with the env vars to poke at throwaway data.

```bash
xcodebuild test -project xwaste.xcodeproj -scheme xwaste -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build_output
```

```bash
xcodebuild test -project xwaste.xcodeproj -scheme xwaste-watch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -derivedDataPath build_output
```

Do **not** pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild test` — it strips the entitlements, CloudKit store loading fails, and the host app's `fatalError` kills the test runner. Simulator builds ad-hoc sign on their own.

## Specs are the contract

The living requirements are in `openspec/specs/` — six capabilities: `grocery-items`, `item-categorization`, `shopping-list`, `home-inventory`, `duplicate-warning`, `household-sharing`. Read the relevant spec before changing behavior; propose changes with `/opsx:propose`. Validate with `openspec validate <change> --strict` (the change name is **positional** — there is no `--change` flag on `validate`).

## Non-negotiables

- **Categorization must never use AI, ML, or a network call.** It is a static compiled-in keyword table. This is an explicit user requirement, not a performance choice.
- **Core Data with `NSPersistentCloudKitContainer`, never SwiftData.** SwiftData mirrors only the private CloudKit database; `CKShare` needs Core Data. See the reversed decision in the archived `design.md`.
- **Destructive actions get an undo path.** The user asked for this directly.
- **Warn, never block.** A duplicate warning informs; it does not prevent the add.

## OpenWolf

@.wolf/OPENWOLF.md

This project uses OpenWolf for context management. Read and follow .wolf/OPENWOLF.md every session. Check .wolf/cerebrum.md before generating code — it carries project-specific gotchas that are not visible in the code. Check .wolf/anatomy.md before reading files.
