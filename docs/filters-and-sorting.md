# Feature: Filters and Sorting

## Purpose

Filters and sorting let users reduce large local catalogs to relevant content while preserving predictable, provider-scoped behavior across browse, search, recommendations, and category grouping.

## Status

- Target state: filters are local, composable, provider-scoped, and consistent across feature surfaces. Group/prefix filtering is implemented first; rating is supported; genre, country/language, recency, audio language, and subtitle language remain metadata-backed expansion points that must not appear until populated local fields can support them honestly.
- Implementation status (reviewed 2026-07-10): `BrowseScreen`, `SearchScreen`, and `LiveScreen` share local filter semantics for category, category group/prefix, minimum rating, normalized text, and deterministic title/newest/rating sorts. Hidden groups are applied consistently to Browse, Search, Live, and For You; full category relationships remain available for filter options even when groups are hidden. Search derivation uses prebuilt category/favorite/activity indexes instead of repeated linear lookups.
- Current schema limitation: rich metadata can be persisted during list/detail hydration, but filter UI remains limited to fields populated broadly enough to be truthful. Prefix visibility is stored in provider-scoped `CategoryPrefixVisibility` database rows; catalog category/media rows remain singleton active-provider state.

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

- Current filter state: `searchText`, selected category, selected category group/prefixes, and minimum rating in browse/search; provider-scoped hidden prefix visibility in Settings.
- Current sort state: `BrowseSort.title`, `.newest`, and `.rating` are applied in memory with deterministic tie-breakers after local fetches.
- Current usable fields for exposed filters: normalized `Media.title`, `Media.rating`, `Media.updatedAt`, `Media.categoryID`, `Media.sourceID`, and `Category.title`.
- Planned fields for future filters: persisted `Media.genre`, `Media.releaseDate`, `Media.addedAt`, `Media.country`, and real audio/subtitle language metadata once population coverage and UI contracts are implemented.

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

- Audio/subtitle language filters require metadata not currently stored in the library schema.
- Genre, release-period, country/language, and added-date values can now be persisted during detail enrichment, but filter UI is intentionally deferred until those fields are populated broadly enough to avoid misleading empty filters.
- Prefix visibility is persisted per provider in local database rows and invalidated through a revisioned visibility cache.
- For You applies the same hidden-prefix relationships to every catalog-derived hero and rail.

## Notes for Agents

- Do not implement filter UI that cannot be backed by local data or a declared local index.
- When adding metadata-backed filters, update mapper, sync, schema/index, search, browse, and docs together.
- If implementing audio/subtitle language filters, distinguish library filtering from player default track selection.
