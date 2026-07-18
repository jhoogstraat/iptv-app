# Feature: Filters and Sorting

## Purpose

Filters and sorting let users reduce large local catalogs to relevant content while preserving predictable, provider-scoped behavior across browse, search, recommendations, and category grouping.

## Status

- Target state: filters are local, composable, provider-scoped, and consistent across feature surfaces. Group/prefix filtering is implemented first; rating is supported; genre, country/language, recency, audio language, and subtitle language remain metadata-backed expansion points that must not appear until populated local fields can support them honestly.
- Implementation status (reviewed 2026-07-18): Category is navigation context in Movies, Series, and Live, not a filter. Their landing screens own category Group/search state; native category destinations own separate media filters and search state. Group controls use searchable multi-select modal sheets with explicit Apply. Movie/series destinations expose rating and title/newest/rating sorting, while Live destinations expose title/newest sorting. Global Search retains Category and Group as result-refinement filters. Each provider selects an automatic, wrapped-pipe, leading-pipe, bracketed, or disabled category-grouping convention; changing it locally recalculates persisted group keys before any filtering runs. Stored results are computed off the main actor from Sendable snapshots, text input is debounced, cancellation propagates into the worker, and cancelled results are rejected. Compact task identities contain criteria and a catalog revision rather than complete row arrays. Bulk result replacement is not animated. Hidden groups are applied consistently to Browse, Search, Live, and For You; full category relationships remain available even when groups are hidden.
- Current schema limitation: rich metadata can be persisted during list/detail hydration, but filter UI remains limited to fields populated broadly enough to be truthful. Prefix visibility is stored in provider-scoped `CategoryPrefixVisibility` database rows; catalog category/media rows remain singleton active-provider state.

## User Experience

- Users can narrow browsing/search by category group or prefix.
- Users should be able to combine filters without surprising OR/AND behavior.
- Active filters should be visible and removable.
- Sorting should be deterministic and stable under ties.
- Missing metadata should be handled explicitly, not silently treated as matching every filter.

### Browse Filter Bar UI

- Category landing bars are horizontally scrolling and expose a searchable Groups sheet. Movie/series destinations use a separate summary/remove-all, Rating, and Sort bar. Live destinations expose Sort. No category destination shows Category or Group as active media filters.
- Search additionally retains a Category pill. When groups are selected there, the Category menu lists only categories in those groups; clearing group selection restores every visible category.
- Filter pills use concise text, badges, active colors, chevrons, and minimum touch targets without redundant leading icons. A selected Groups pill replaces its default `Groups` title with the selected group names. Menu rows retain their explanatory icons.
- With no active filters, the summary control is hidden. With active filters, it animates in as a `line.3.horizontal.decrease` reset pill with the active filter-group count. Tapping it opens a small menu whose sole action is `Reset All Filters`; its VoiceOver label states the active filter count and that reset options are available.
- Category remains a dedicated sibling filter only in global Search; the media tabs use their sectioned landing lists for category navigation.
- Filter buttons may choose one of three presentation styles depending on filter shape and platform:
  - Small enum filters use a compact popover/menu with a short set of options, for example release period values such as `This Year`, `Last Year`, decade ranges, or `Custom`.
  - Large option sets use a modal sheet or full-screen selector with an optional search field, selectable rows, checkmarks, cancel/close affordance, and explicit apply/confirm affordance when selection is not committed immediately. Category and language filters should use this pattern when their option count is high.
  - Platform-adaptive filters may use popovers on iPad/macOS-style layouts and sheets/full-screen presentation on compact iPhone layouts when the same filter would otherwise be cramped.
- Multi-select filters must show OR semantics within the filter group; combining different filter groups remains AND semantics.
- The filter bar should support clearing individual active filters from their button or modal where practical, while the animated summary control remains the canonical clear-all entry point.
- The UI must preserve accessibility: minimum tappable target size, VoiceOver labels that include active/inactive state and selection count, Dynamic Type support without truncating essential values, and keyboard/focus navigation on platforms that expose it.

## Data and State

- Current filter state is surface-specific: category landing search plus selected group/prefixes; media destination search plus rating/sort for movies and series or search/sort for Live; global Search retains selected category, groups, rating, and scope. Provider-scoped hidden prefix visibility remains in Settings.
- Current sort state: `BrowseSort.title`, `.newest`, and `.rating` are applied in memory with deterministic tie-breakers after local fetches.
- Current usable fields for exposed filters: normalized `Media.title`, `Media.rating`, `Media.updatedAt`, `Media.categoryID`, `Media.sourceID`, `Category.title`, and persisted `Category.groupKey`.
- Browse/Search/Live filtering and sorting receive already-fetched `Media` and `Category` snapshots and perform no provider work in their worker tasks. Category-prefix derivation occurs only when category rows are written or locally reclassified after a provider grouping-style change; workers use the persisted group key, normalize each query once, and check cancellation while scanning and before/after sorting.
- Hydration counts come from a compact grouped database observation. Browse and Live scope their row observations to the selected category, so category commits do not reduce or equality-compare the complete catalog on the main actor.
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
- Rapid query/filter changes cancel obsolete work and never commit stale results.

## Current Gaps / Planned Work

- Audio/subtitle language filters require metadata not currently stored in the library schema.
- Genre, release-period, country/language, and added-date values can now be persisted during detail enrichment, but filter UI is intentionally deferred until those fields are populated broadly enough to avoid misleading empty filters.
- Prefix visibility is persisted per provider in local database rows and invalidated through a revisioned visibility cache.
- For You applies hidden-prefix relationships in its observed database projection and fetches only bounded rail candidates rather than scanning the complete media catalog.

## Notes for Agents

- Do not implement filter UI that cannot be backed by local data or a declared local index.
- When adding metadata-backed filters, update mapper, sync, schema/index, search, browse, and docs together.
- If implementing audio/subtitle language filters, distinguish library filtering from player default track selection.
