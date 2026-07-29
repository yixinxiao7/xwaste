# household-sharing Specification

## Purpose

Sync household data across a user's devices via iCloud with no account system, let users invite others to a shared household with read-write access, and degrade gracefully to a fully functional local-only app.

## Requirements

### Requirement: No account system

The system SHALL use the device's iCloud account as the user's identity. The system SHALL NOT present a sign-up screen, a password field, a profile, or any authentication step of its own.

#### Scenario: First launch requires no setup

- **WHEN** a user launches the app for the first time
- **THEN** they arrive at a usable shopping list with no sign-in, no onboarding account step, and no permission prompt beyond what the system itself presents

### Requirement: Sync across a user's own devices

When an iCloud account is available, the system SHALL synchronize all household data across every device signed into that account. Synchronization SHALL happen in the background without the user invoking it.

#### Scenario: A second device catches up

- **WHEN** a user adds items on one device and opens the app on another device signed into the same iCloud account
- **THEN** the items appear on the second device without any manual sync, import, or refresh action

#### Scenario: Edits converge

- **WHEN** a user edits an item on one device
- **THEN** the edit appears on their other devices, and no device is left holding a stale copy indefinitely

### Requirement: Graceful degradation without iCloud

The system SHALL remain fully functional as a local-only app when no iCloud account is signed in, when iCloud Drive is disabled, or when the account has no available storage. The system SHALL communicate that sync is unavailable without presenting an error state, a blocking dialog, or an empty screen.

#### Scenario: No iCloud account signed in

- **WHEN** a user with no iCloud account uses the app
- **THEN** every list, inventory, categorization, and warning feature works locally, and the app indicates that sync is off rather than appearing broken

#### Scenario: Sharing is unavailable rather than broken

- **WHEN** a user without iCloud looks for sharing
- **THEN** the sharing entry point explains that it requires iCloud, rather than failing silently or crashing

### Requirement: Invite others to a household

The system SHALL let a user invite other iCloud users to their household through the system share sheet. Invited participants SHALL receive read-write access to the household's shopping list and home inventory as a single unit.

#### Scenario: Sending an invitation

- **WHEN** a user chooses to share their household
- **THEN** the system share sheet is presented so they can send an invitation through any channel the system offers

#### Scenario: Participants get read-write access

- **WHEN** a participant accepts an invitation
- **THEN** they can add, edit, check off, and delete items, and their changes reach the other members

### Requirement: Accepting an invitation joins the shared household

When a user accepts an invitation, the system SHALL open to the shared household's shopping list and inventory rather than their own previously local data.

#### Scenario: Accepting from a link

- **WHEN** a user taps an invitation link
- **THEN** the app opens, accepts the invitation, and shows the shared household's list and inventory

#### Scenario: Shared data is what the features act on

- **WHEN** a participant is in a shared household and adds an item that another member already stocked
- **THEN** the duplicate warning is evaluated against the shared inventory, not against the participant's former local data

### Requirement: A user is in one active household at a time

The system SHALL treat exactly one household as active. Accepting an invitation SHALL make the shared household active while preserving the user's own household untouched rather than merging, overwriting, or deleting it. This change covers a user belonging to at most one shared household at a time; what happens when a user who is already in a shared household accepts an invitation to a second one is out of scope here.

#### Scenario: Personal data is preserved on joining

- **WHEN** a user with existing local items accepts an invitation to another household
- **THEN** their own items are retained and are not merged into the shared household

#### Scenario: Leaving restores the personal household

- **WHEN** a participant leaves a shared household
- **THEN** their own household becomes active again with its items intact

### Requirement: See who is in the household

The system SHALL show the current members of a shared household.

#### Scenario: Viewing members

- **WHEN** a user opens the household screen for a shared household
- **THEN** the members are listed, including which one owns it

#### Scenario: Unshared household

- **WHEN** a household has not been shared
- **THEN** the screen offers to invite someone rather than showing an empty member list

### Requirement: Leaving and revoking access

The system SHALL let a participant leave a shared household and SHALL let the owner stop sharing or remove a participant. After either action, the removed user SHALL no longer see the household's items, and the remaining members SHALL retain theirs.

#### Scenario: Participant leaves

- **WHEN** a participant leaves a household
- **THEN** they no longer see its list or inventory, and the remaining members keep all items

#### Scenario: Owner stops sharing

- **WHEN** the owner stops sharing a household
- **THEN** participants lose access, the owner retains every item, and no member is left with a partially populated or corrupted list

#### Scenario: Leaving is confirmed before it happens

- **WHEN** a user chooses to leave a household or stop sharing
- **THEN** the system confirms the action first, since it is not reversible from within the app without a new invitation

### Requirement: Changes propagate between members

A change made by one household member SHALL become visible to the other members without requiring a manual refresh or an app restart.

#### Scenario: Partner adds to the list while you are shopping

- **WHEN** one member adds an item to the shared shopping list
- **THEN** the item appears on the other members' lists once the change syncs, without them taking any action

#### Scenario: Check-off reaches the other members

- **WHEN** one member checks an item off while shopping
- **THEN** the item leaves the shared list and appears in the shared inventory for every member

### Requirement: Sharing never blocks local use

The system SHALL apply every user action to local storage immediately and SHALL NOT make any list or inventory operation wait on a network round-trip, a sync completion, or the availability of other members.

#### Scenario: Shopping in a store with no signal

- **WHEN** a member uses the app with no usable connection
- **THEN** adds, edits, and check-offs all succeed immediately and are transmitted once a connection returns

#### Scenario: Sync state is visible but not intrusive

- **WHEN** changes are pending upload
- **THEN** the user may see an unobtrusive indication of sync state, and SHALL NOT be blocked, interrupted, or prevented from continuing
