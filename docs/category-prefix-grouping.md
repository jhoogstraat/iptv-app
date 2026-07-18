# Feature: Category Prefix Grouping

## Purpose

Category prefix grouping organizes provider categories by provider-encoded prefixes so large libraries can be navigated by language, region, source grouping, or other provider naming conventions.

## Status

- Target state: detected category prefixes are first-class local organization metadata that can group category pickers, hide/show category groups, and feed search/recommendation filters consistently.
- Implementation status (reviewed 2026-07-18): category sync applies a provider-scoped built-in grouping convention and persists indexed `Category.groupKey` plus `Category.displayName` metadata. Automatic grouping recognizes `|DE| Movies`, `DE| Movies`, `LAT|Movies`, and `[DE] Movies`; Settings also offers individual wrapped-pipe, leading-pipe, bracketed, and disabled modes. A mode change atomically reclassifies the active local catalog without a remote sync. Movies, Series, and Live use the keys as section titles while category rows use the persisted display name; Browse, Search, and Live expose searchable multi-select group sheets; `SettingsScreen` hides detected groups per provider through `CategoryPrefixVisibilityStore`; and local database/filter requests apply hidden or selected groups consistently.
- Current limitation: grouping depends entirely on the raw provider category title. Custom templates/regular expressions, normalized category metadata, language source configuration, and recommendation-facing selected-group filters are not implemented.

## User Experience

- Movies, Series, and Live open on category lists sectioned by detected group. Category row labels omit a matching pipe prefix because the section already communicates it. Group filters open searchable multi-select sheets, and landing search narrows the category lists before native navigation; pushed media screens use independent media filter state. Search retains category and group filters for global result refinement.
- Unprefixed categories should remain visible under a fallback group.
- Users can hide provider prefix groups in Settings, and those provider-scoped choices apply across Browse, Search, Live, and For You.
- Language grouping should be configurable separately from raw provider category names when enough metadata exists.

## Data and State

- Current grouping source: `Category.title` at the category-sync write boundary, interpreted by `CategoryGroupingStyle` from the provider-owned `category_grouping_settings` record.
- Current parser: automatic mode tries wrapped-pipe, leading-token pipe, and bracketed forms in that order; explicit modes apply only their selected convention. It persists both the extracted `Category.groupKey` and display-safe `Category.displayName`, preserving the provider-owned raw title for storage and relationships.
- `categories(type, groupKey)` is indexed for category/group projections. Category conflict updates persist title and group key together so provider renames incrementally update the index.
- Current Movies/Series/Live landing state stores selected category-group keys but no selected category. A concrete category is passed as native navigation context, and its destination observes only that category's rows. Global Search continues to combine selected category and group keys as local result filters.
- Prefix visibility is persisted per provider in the local `category_prefix_visibility` table and invalidated through the revisioned `CategoryPrefixVisibilityStore` cache.

## Key Files

- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/LibraryFilters.swift`
- `iptv/Model/Mapper.swift`

## Target Acceptance Criteria

- Category grouping is deterministic and stable for a given provider catalog.
- Categories without a recognized prefix remain accessible.
- Prefix visibility settings apply consistently to browse, search, and recommendation surfaces.
- Prefix extraction does not destroy the original provider category title.
- Prefix preferences are provider-scoped so one provider's hidden groups do not affect another provider.
- Grouping-style changes locally reclassify the active provider catalog and update category display labels without a remote resync.
- Group labels are display-safe and do not expose parsing artifacts when avoidable.

## Current Gaps / Planned Work

- Recommendation surfaces apply provider-hidden groups but do not expose interactive selected-group filters.
- Custom grouping templates/regular expressions are intentionally deferred; normalized provider-agnostic grouping metadata and language-source configuration remain planned.

## Notes for Agents

- Do not add provider-specific conventions without a provider-scoped built-in style and tests for extraction, display labels, and local reclassification.
- If prefix filtering is implemented, update `docs/filters-and-sorting.md`, `docs/search.md`, and `docs/for-you.md` because prefix visibility affects those features too.
- Be explicit about whether a new filter uses raw provider category title, normalized prefix, language code, or user preference state.
