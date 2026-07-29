# item-categorization Specification

## Purpose

Assign every item a category deterministically and offline, using a static compiled-in keyword table over a fixed category set, with a sticky manual override. Never uses AI, ML, or a network call.

## Requirements

### Requirement: Deterministic offline categorization

The system SHALL assign a category to an item by matching its name against a static keyword table compiled into the app. The system SHALL NOT use artificial intelligence, machine learning, language models, or any remote service to categorize items. Categorization SHALL be deterministic: the same item name SHALL always produce the same category.

#### Scenario: Category assigned on add

- **WHEN** a user adds an item named "Broccoli"
- **THEN** the item is placed in the "Produce" category without any user action

#### Scenario: Categorization requires no network

- **WHEN** the device has no network connection and a user adds "Broccoli"
- **THEN** the item is categorized as "Produce" exactly as it would be with a connection, with no delay and no error

#### Scenario: Repeated categorization is stable

- **WHEN** the same name is categorized on two separate occasions
- **THEN** both occasions produce the same category

### Requirement: Fixed category set

The system SHALL support exactly these categories, displayed in this fixed order: Produce, Dairy & Eggs, Meat & Seafood, Bakery, Frozen, Pantry, Beverages, Snacks, Household, Other. "Other" SHALL always sort last.

#### Scenario: Sections appear in the fixed order

- **WHEN** a list contains items in the Pantry, Produce, and Other categories
- **THEN** the sections are displayed in the order Produce, Pantry, Other

### Requirement: Keyword table is keyed on normalized names

Every key in the keyword table SHALL be stored in the same normalized form that item names are put through before matching, so that a term whose natural spelling carries a plural suffix remains reachable. A key written in its natural spelling SHALL NOT be relied upon to match.

#### Scenario: A naturally plural term still matches

- **WHEN** a user adds "Asparagus", a term whose normalized form differs from its natural spelling
- **THEN** the item is categorized as Produce rather than falling through to Other

#### Scenario: A plural-only term still matches

- **WHEN** a user adds "Tortilla Chips"
- **THEN** the item is categorized as Snacks, because the table's key for chips is stored in the same normalized form the name is matched in

### Requirement: Keyword matching rules

The system SHALL categorize a name by first normalizing it, then applying, in order:

1. An exact match of the whole normalized name against the keyword table.
2. Otherwise, among every keyword that appears in the normalized name **on word boundaries**, the keyword whose final character falls **latest** in the name. A keyword SHALL NOT match part of a longer word.
3. Otherwise, the "Other" category.

When two matching keywords end at the same position, the system SHALL choose the longer one. When two keywords of equal length end at the same position, the system SHALL choose the category that appears earliest in the fixed category order. The result SHALL therefore never depend on the order in which the table is stored or iterated.

Rightmost-match-wins reflects how grocery names are built: the last noun is what the item *is*, and the words before it are modifiers.

#### Scenario: Modifier words do not defeat matching

- **WHEN** a user adds "organic baby spinach"
- **THEN** the word "spinach" matches and the item is categorized as Produce

#### Scenario: Numeric and symbolic prefixes are ignored

- **WHEN** a user adds "2% milk"
- **THEN** the word "milk" matches and the item is categorized as Dairy & Eggs

#### Scenario: The rightmost match decides a compound name

- **WHEN** a user adds "potato chips" and the table contains both "potato" (Produce) and "chips" (Snacks)
- **THEN** the item is categorized as Snacks, because "chips" ends later in the name, even though "potato" is the longer keyword

#### Scenario: A multi-word keyword beats the words inside it

- **WHEN** a user adds "vanilla ice cream" and the table contains both "ice cream" (Frozen) and "cream" (Dairy & Eggs)
- **THEN** the item is categorized as Frozen, because both keywords end at the same position and "ice cream" is longer

#### Scenario: Word order changes the category

- **WHEN** a user adds "chocolate milk" and later adds "milk chocolate"
- **THEN** "chocolate milk" is categorized as Dairy & Eggs and "milk chocolate" as Snacks, each taking the category of its final word

#### Scenario: A keyword does not match inside a longer word

- **WHEN** a user adds "barbecue sauce" and the table contains "bar" (Beverages)
- **THEN** "bar" does not match inside "barbecue", and the item takes the category of "sauce"

### Requirement: Unrecognized names fall back to Other

When no keyword matches an item's name, the system SHALL assign the "Other" category rather than guessing or failing.

#### Scenario: Unknown product name

- **WHEN** a user adds an item named "Zorbex"
- **THEN** the item is categorized as "Other" and appears in the Other section

#### Scenario: Other section is usable

- **WHEN** items fall into "Other"
- **THEN** they are displayed, editable, checkable, and countable exactly like items in any other category

### Requirement: Recategorization on rename

When an item's name changes and its category has not been set manually, the system SHALL recompute the category from the new name.

#### Scenario: Rename moves the item to a new section

- **WHEN** a user renames an automatically categorized item from "Milk" to "Bagels"
- **THEN** the item moves from the Dairy & Eggs section to the Bakery section

### Requirement: Manual category override is sticky

The system SHALL allow a user to set an item's category manually from the fixed category set. Once set manually, the system SHALL preserve that category and SHALL NOT overwrite it during a later rename. The system SHALL allow the user to return the item to automatic categorization, which immediately recomputes the category from the current name.

#### Scenario: Manual choice survives a rename

- **WHEN** a user manually sets "Bagels" to the Frozen category and later renames it to "Everything Bagels"
- **THEN** the item stays in the Frozen category

#### Scenario: Returning to automatic

- **WHEN** a user reverts a manually categorized item named "Bagels" to automatic categorization
- **THEN** the item is immediately recategorized as Bakery

#### Scenario: Override persists across launches

- **WHEN** a user manually categorizes an item, quits the app, and relaunches
- **THEN** the item retains the manually chosen category
