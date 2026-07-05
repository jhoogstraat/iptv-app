# Feature: Filters and Sorting

## Purpose

Filters and sorting let users reduce large local catalogs to relevant content while preserving predictable, provider-scoped behavior across browse, search, recommendations, and category grouping.

## Status

- Target state: filters are local, composable, provider-scoped, and consistent across feature surfaces. Group/prefix filtering is implemented first; rating, genre, language, recency, audio language, and subtitle language are planned metadata-backed filters.
- Current implementation: selected-category title filtering exists in `BrowseScreen`; prefix grouping exists in the category menu; global filters are not implemented; `BrowseSort` exists but is not applied.
- Current schema limitation: `Media` has title, rating, category, cover URL, TMDB ID, and timestamps, but no genre, year, language, added date, audio track, or subtitle track fields.

## User Experience

- Users can narrow browsing/search by category group or prefix.
- Users should be able to combine filters without surprising OR/AND behavior.
- Active filters should be visible and removable.
- Sorting should be deterministic and stable under ties.
- Missing metadata should be handled explicitly, not silently treated as matching every filter.

### Browse Filter Bar UI

- The existing top-left category selector in `BrowseScreen` should become the leading item in a horizontally scrolling filter bar that can host multiple filter buttons.
- The visual model should follow the official GitHub iOS app filter style: compact rounded pills, dark neutral inactive state, blue active state, concise labels, and chevrons on buttons that open choices.
- Active filters use a blue-tinted background and high-contrast foreground text. Inactive filters use the standard dark/secondary pill treatment and should remain visually available without competing with active filters.
- The leftmost control is a filter summary button with a filter icon and numeric badge/count when one or more filters are active. Activating it opens a compact popover/menu that states how many filters are applied and offers a destructive `Clear All Filters` action.
- The current category selector becomes one filter button in this bar. It should still support quick category selection, but the UI must allow additional sibling filters such as rating, release period, language, genre, audio language, and subtitle language.
- Filter buttons may choose one of three presentation styles depending on filter shape and platform:
  - Small enum filters use a compact popover/menu with a short set of options, for example release period values such as `This Year`, `Last Year`, decade ranges, or `Custom`.
  - Large option sets use a modal sheet or full-screen selector with an optional search field, selectable rows, checkmarks, cancel/close affordance, and explicit apply/confirm affordance when selection is not committed immediately. Category and language filters should use this pattern when their option count is high.
  - Platform-adaptive filters may use popovers on iPad/macOS-style layouts and sheets/full-screen presentation on compact iPhone layouts when the same filter would otherwise be cramped.
- Multi-select filters must show OR semantics within the filter group; combining different filter groups remains AND semantics.
- The filter bar should support clearing individual active filters from their button/menu where practical, while the summary popover remains the canonical clear-all entry point.
- The UI must preserve accessibility: minimum tappable target size, VoiceOver labels that include active/inactive state and selection count, Dynamic Type support without truncating essential values, and keyboard/focus navigation on platforms that expose it.

## Data and State

- Current filter state: `searchText` in `BrowseScreen`, `selectedCategoryID`, planned prefix visibility in Settings.
- Current sort state: `BrowseSort.title`, `.newest`, `.rating` exists but does not affect the query.
- Current usable fields: `Media.title`, `Media.rating`, `Media.updatedAt`, `Media.categoryID`, `Category.title`.
- Planned fields/indexes: normalized category prefix/group, rating bounds, genre, year, original added date, language, audio language, subtitle language, and provider-scoped visibility preferences.

## Key Files

- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`
- `docs/category-prefix-grouping.md`
- `docs/search.md`

## Target Acceptance Criteria

- Filters operate over local persisted data or local indexes.
- Filter semantics are documented: AND across filter groups, OR within multi-select groups.
- Group/prefix visibility affects browse, search, and recommendations consistently.
- Rating filters exclude items with missing ratings when a rating predicate is active.
- Language filters state whether they use catalog metadata, inferred category prefix, audio track metadata, subtitle track metadata, or user preferences.
- Sort order has deterministic tie-breakers, such as title and source ID.
- Filter state is provider-scoped when persisted.

## Current Gaps / Planned Work

- No multi-button browse filter bar, filter summary button, popovers, or modal filter selectors exist.
- `BrowseSort` is unused.
- Prefix visibility controls in Settings are disabled/TODO.
- Min rating can use current `Media.rating`, but the UI and query wiring are absent.
- Audio/subtitle language filters require metadata not currently stored in the library schema.
- Genre, year, recency, and language filters require schema or search-index expansion.

## Notes for Agents

- Do not implement filter UI that cannot be backed by local data or a declared local index.
- When adding metadata-backed filters, update mapper, sync, schema/index, search, browse, and docs together.
- If implementing audio/subtitle language filters, distinguish library filtering from player default track selection.
