## Purpose

Store the household's recipes — name, optional photo, description, per-serving ingredient counts, and ordered steps — and show at a glance which ones the At Home inventory can make, which ingredients fall short, and put exactly the shortfall on the shopping list.

## ADDED Requirements

### Requirement: Recipe record

The system SHALL persist every recipe as a record containing a display name, an optional image, an optional short description, an ordered list of ingredients, an ordered list of steps, a creation timestamp, and the household the recipe belongs to. Each ingredient SHALL carry a display name, a normalized name derived by the same normalization rule used for grocery items, and a whole-number count of one or greater representing what one serving needs. Every recipe SHALL belong to exactly one household.

#### Scenario: Recipe created with complete record

- **WHEN** a user saves a recipe named "Buttered Toast" with description "Two minutes, one pan", ingredients "Butter" ×1 and "Bread" ×2, and steps "Toast the bread" then "Spread the butter"
- **THEN** the system stores one recipe with that name and description, two ingredients with normalized names "butter" and "bread" and counts 1 and 2 in that order, two steps in that order, the current timestamp, and a reference to the user's household

#### Scenario: Blank names are rejected

- **WHEN** a user attempts to save a recipe whose name is empty or only whitespace
- **THEN** the recipe is not created and the editor stays open with the entered values intact

#### Scenario: Blank ingredient and step rows are dropped

- **WHEN** a user saves a recipe whose editor contains an ingredient row with an empty name and a step row with empty text
- **THEN** the saved recipe omits those rows and keeps every non-blank row in its entered order

#### Scenario: Duplicate ingredient names merge

- **WHEN** a user saves a recipe listing "Onion" ×1 and "onions" ×2 as separate ingredient rows
- **THEN** the saved recipe holds a single onion ingredient with count 3, keeping the first row's display name and position

#### Scenario: Recipes survive app restart

- **WHEN** a user creates a recipe, force-quits the app, and relaunches it
- **THEN** the recipe reappears with its name, image, description, ingredients, and steps unchanged

### Requirement: Recipes tab

The system SHALL provide a "Recipes" screen as a third top-level tab beside Shopping List and At Home, with an add control in its toolbar that opens the recipe editor. Shopping List SHALL remain the default screen on launch.

#### Scenario: Reaching recipes

- **WHEN** a user launches the app
- **THEN** the Shopping List is shown and a Recipes tab is available beside At Home

#### Scenario: Starting a new recipe

- **WHEN** a user taps the add control on the Recipes screen
- **THEN** the recipe editor is presented with the name field active, and Cancel returns to the Recipes screen without creating anything

#### Scenario: No recipes yet

- **WHEN** the household has no recipes
- **THEN** the Recipes screen shows a message explaining what recipes do and offering to add the first one, rather than a blank screen

### Requirement: Recipe tiles

The Recipes screen SHALL display every recipe in the household as a tile showing the recipe's image, its name, and its availability status icon, in a grid ordered by name. A recipe with no image SHALL display a default placeholder image in the image's place. Tiles SHALL be rendered lazily so the grid scrolls continuously through any number of recipes with no paging control and no visible loading step.

#### Scenario: Tile with a photo

- **WHEN** a recipe has an image
- **THEN** its tile shows that image with the recipe name and status icon

#### Scenario: Tile without a photo

- **WHEN** a recipe has no image
- **THEN** its tile shows the default placeholder where the image would be, with the name and status icon as usual

#### Scenario: Large collection scrolls without paging

- **WHEN** the household has two hundred recipes
- **THEN** the user scrolls through all of them in one continuous grid, with no "load more" control and no perceptible stall

#### Scenario: Tapping a tile opens the recipe

- **WHEN** a user taps a tile
- **THEN** the recipe page for that recipe is shown

### Requirement: Availability status

For every recipe the system SHALL determine whether it can be made from the household's home inventory: a recipe can be made when, for each ingredient, an At Home item with the same normalized name holds a quantity of at least the ingredient's count. A recipe with no ingredients can be made. The status SHALL be shown as a check mark when the recipe can be made and an x otherwise, SHALL be computed from local storage without a network round-trip, and SHALL reflect inventory changes as soon as they are visible on the At Home screen.

#### Scenario: Every ingredient covered

- **WHEN** a recipe needs "Butter" ×1 and "Bread" ×2, and At Home holds "Butter" ×1 and "Bread" ×4
- **THEN** the recipe shows a check mark

#### Scenario: A count falls short

- **WHEN** a recipe needs "Onion" ×3 and At Home holds "Onion" ×1
- **THEN** the recipe shows an x

#### Scenario: An ingredient is absent

- **WHEN** a recipe needs "Garlic" ×1 and no garlic is at home
- **THEN** the recipe shows an x

#### Scenario: Plural and case do not matter

- **WHEN** a recipe lists "onions" ×2 and At Home holds "Onion" ×3
- **THEN** the two are treated as the same ingredient and the recipe shows a check mark

#### Scenario: Shopping-list rows do not count

- **WHEN** the only "Onion" in the household is on the shopping list, not At Home
- **THEN** a recipe needing onions shows an x

#### Scenario: Status follows the inventory

- **WHEN** a recipe shows a check mark and a user decrements a required ingredient at home below the recipe's count
- **THEN** the recipe's tile and page show an x the next time they are displayed, with no manual refresh

### Requirement: Filter recipes by availability

The Recipes screen SHALL offer a filter with three choices — all recipes, recipes that can be made, and recipes that cannot — defaulting to all. Changing the filter SHALL update the grid immediately.

#### Scenario: Showing only what can be cooked

- **WHEN** the household has a recipe that can be made and one that cannot, and the user picks the can-make filter
- **THEN** only the recipe with a check mark remains in the grid

#### Scenario: Showing what is missing something

- **WHEN** the user picks the missing filter
- **THEN** only recipes with an x remain in the grid

#### Scenario: Filtered-out empty state

- **WHEN** the chosen filter matches no recipe but the household has recipes
- **THEN** the grid shows a message that no recipes match the filter, distinct from the no-recipes-yet message

### Requirement: Recipe page

The system SHALL provide a recipe page showing the recipe's name with its availability status icon beside it, the image or placeholder, the description, the ingredients with their counts in order, and the steps in order. Each ingredient whose At Home quantity does not cover its count SHALL be marked with an x; covered ingredients SHALL NOT be marked with an x.

#### Scenario: Viewing a recipe with a shortfall

- **WHEN** a recipe needs "Butter" ×1 and "Onion" ×3, and At Home holds "Butter" ×1 and "Onion" ×1
- **THEN** the page shows an x beside the name, an x beside "Onion" ×3, and no x beside "Butter" ×1

#### Scenario: Viewing a recipe that can be made

- **WHEN** every ingredient of a recipe is covered
- **THEN** the page shows a check mark beside the name and no ingredient is marked

### Requirement: Edit and delete recipes

The system SHALL let a user edit every field of an existing recipe, including replacing or removing its image, and delete a recipe outright. After a deletion the system SHALL display an undo control naming the recipe, available for at least five seconds while the Recipes screen is on screen and dismissible by the user; activating it SHALL restore the recipe with its name, image, description, ingredients, and steps intact. Letting the control expire SHALL change nothing further.

#### Scenario: Editing updates the tile

- **WHEN** a user renames "Buttered Toast" to "Cheese Toast" and adds "Cheese" ×1 with no cheese at home
- **THEN** the tile shows "Cheese Toast" with an x

#### Scenario: Deleting and undoing

- **WHEN** a user deletes "Onion Soup" and activates the undo control
- **THEN** "Onion Soup" reappears with all of its ingredients, steps, description, and image

#### Scenario: Undo expires

- **WHEN** a user deletes a recipe and lets the undo control disappear
- **THEN** the recipe stays deleted and nothing further changes

#### Scenario: Removing the image

- **WHEN** a user removes a recipe's image in the editor and saves
- **THEN** the tile and page show the default placeholder

### Requirement: Ingredient entry shows what is at home

While a user types an ingredient name in the recipe editor, the system SHALL display an inline, non-modal note of how many of that ingredient are At Home as soon as the typed name matches an inventory item, without interrupting typing or blocking saving, so the user can spell ingredients the way the inventory does.

#### Scenario: Matching an inventory item while typing

- **WHEN** At Home holds "Onion" ×3 and the user types "onion" into an ingredient name field
- **THEN** a note stating 3 are at home appears beneath the field while typing continues

#### Scenario: No match shows nothing

- **WHEN** the typed name matches nothing at home
- **THEN** no note is shown

### Requirement: Add missing ingredients to the shopping list

When a recipe cannot be made, the recipe page SHALL offer a single action that puts the shortfall on the shopping list. For each ingredient whose At Home quantity is below its count, the shortfall is the count minus the At Home quantity; the action SHALL raise that ingredient's shopping-list quantity to at least the shortfall — creating the list row if absent, leaving it unchanged if it already covers the shortfall — so that repeating the action adds nothing more. Rows created this way SHALL be categorized by the same rule as any other added item. The action SHALL NOT present the already-at-home warning, because the shortfall already accounts for what is at home. The action SHALL NOT be offered when the recipe can be made.

#### Scenario: Adding the shortfall

- **WHEN** a recipe needs "Onion" ×3 and "Garlic" ×1, At Home holds "Onion" ×1, the shopping list holds neither, and the user adds the missing ingredients
- **THEN** the shopping list shows "Onion" ×2 under Produce and "Garlic" ×1 under its automatic category, and At Home is unchanged

#### Scenario: Repeating the action adds nothing

- **WHEN** the user activates the action a second time with nothing else changed
- **THEN** the shopping list still shows "Onion" ×2 and "Garlic" ×1

#### Scenario: List already partly covers the shortfall

- **WHEN** the shortfall for "Onion" is 2 and the shopping list already holds "Onion" ×1
- **THEN** the list row becomes "Onion" ×2

#### Scenario: List already covers the shortfall

- **WHEN** the shortfall for "Onion" is 2 and the shopping list already holds "Onion" ×5
- **THEN** the list row stays "Onion" ×5

#### Scenario: Nothing to add

- **WHEN** a recipe can be made
- **THEN** no add-missing action is shown on its page

### Requirement: Recipe images

A recipe image SHALL be optional and chosen from the user's photo library. The system SHALL store a reduced copy whose longest side is at most 1024 pixels, oriented as the photo was taken, rather than the original, so that images sync promptly and the grid stays responsive. Choosing a photo SHALL NOT require access to the whole photo library.

#### Scenario: Choosing a photo

- **WHEN** a user picks a 12-megapixel photo for a recipe
- **THEN** the stored image is at most 1024 pixels on its longest side, appears the right way up, and the tile shows it

#### Scenario: Picker needs no library permission

- **WHEN** a user opens the photo chooser for the first time
- **THEN** no whole-library permission prompt precedes it

### Requirement: Recipes belong to the household

Recipes SHALL belong to the household, sync across the user's own devices, and reach every household member through the existing household share, exactly as grocery items do. Availability SHALL always be evaluated against the household's At Home inventory. Every recipe operation SHALL work offline and SHALL NOT require an iCloud account.

#### Scenario: A member sees a shared recipe

- **WHEN** one household member creates "Onion Soup" and the change syncs
- **THEN** other members see "Onion Soup" on their Recipes screen without manual refresh, with a status computed against the shared inventory

#### Scenario: Status uses the shared inventory

- **WHEN** one member checks off "Onion" ×3 into the shared inventory and the change syncs
- **THEN** a recipe needing "Onion" ×3 shows a check mark for every member

#### Scenario: Offline use

- **WHEN** the device is in airplane mode
- **THEN** the user can create, edit, delete, and view recipes and their status with no degradation, and the changes sync later
