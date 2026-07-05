# Feature: Category Prefix Grouping

## Purpose

Category prefix grouping organizes provider categories by provider-encoded prefixes so large libraries can be navigated by language, region, source grouping, or other provider naming conventions.

## Status

- Target state: detected category prefixes are first-class local organization metadata that can group category pickers, hide/show category groups, and feed search/recommendation filters consistently.
- Current implementation: `CategoryGrouping` extracts pipe-delimited prefixes from `Category.title`; browse/search filter bars expose category group selection; Settings can hide visible prefixes per provider through `UserDefaults`.
- Current limitation: grouping depends entirely on the raw `Category.title` string supplied by the provider, and normalized category metadata is not yet stored in schema tables.

## User Experience

- Category selection should show groups in a predictable order.
- Unprefixed categories should remain visible under a fallback group.
- Users should eventually be able to choose visible prefixes so unwanted category groups are hidden across browse, search, and recommendations.
- Language grouping should be configurable separately from raw provider category names when enough metadata exists.

## Data and State

- Current grouping source: `Category.title`.
- Current parser: pipe-delimited title pattern, where the first pipe segment becomes the group key.
- Current browse/search state: selected category and selected category-group keys narrow local `Media` results; Settings persists hidden prefix/group keys by provider ID.
- Planned state: normalized prefix/group metadata columns or tables, language source configuration, and provider-scoped visibility preferences stored with the local database.

## Key Files

- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`

## Target Acceptance Criteria

- Category grouping is deterministic and stable for a given provider catalog.
- Categories without a recognized prefix remain accessible.
- Prefix visibility settings apply consistently to browse, search, and recommendation surfaces.
- Prefix extraction does not destroy the original provider category title.
- Prefix preferences are provider-scoped so one provider's hidden groups do not affect another provider.
- Group labels are display-safe and do not expose parsing artifacts when avoidable.

## Current Gaps / Planned Work

- Prefix visibility persistence currently uses provider-scoped `UserDefaults`, not local database rows.
- Search and browse consume prefix visibility; recommendation surfaces cannot until `ForYouScreen` is backed by local recommendation queries.
- The database schema has no prefix/group visibility table or category metadata columns.
- The current regex is narrow and should be treated as an implementation detail, not the final provider-agnostic parser.

## Notes for Agents

- Do not hardcode one provider's category naming convention as a universal rule without keeping raw category titles intact.
- If prefix filtering is implemented, update `docs/filters-and-sorting.md`, `docs/search.md`, and `docs/for-you.md` because prefix visibility affects those features too.
- Be explicit about whether a new filter uses raw provider category title, normalized prefix, language code, or user preference state.
