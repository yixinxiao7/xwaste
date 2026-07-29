# xwaste

An iOS SwiftUI app whose single purpose is **reducing food waste**: the shopping list doubles as a home inventory, so "do I already have onions?" is answerable at the moment of adding.

**Naming:** the app was renamed from `nomorewaste` to `xwaste` on 2026-07-28. The bundle ID (`com.yixinxiao.nomorewaste`), the CloudKit container (`iCloud.com.yixinxiao.nomorewaste`), and the on-disk store filenames (`NoMoreWaste.sqlite`, `NoMoreWaste-shared.sqlite`) deliberately keep the old name — they are bound to the App Store Connect record, a permanent CloudKit container, and existing installs' data. Do not "fix" them.

## Current state

v1 is implemented, verified, and on TestFlight. The `add-grocery-inventory` change is archived at `openspec/changes/archive/2026-07-28-add-grocery-inventory/` (proposal, design, 97-task log). One deferred check: same-account two-device sync (task 10.1) was never exercised.

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
