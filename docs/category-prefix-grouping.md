# Feature: Category Prefix Grouping

## Purpose

Category prefix grouping organizes provider categories by provider-encoded prefixes so large libraries can be navigated by language, region, source grouping, or other provider naming conventions.

## Status

- Target state: detected category prefixes are first-class local organization metadata that can group category pickers, hide/show category groups, and feed search/recommendation filters consistently.
- Implementation status (reviewed 2026-07-10): `CategoryGrouping` extracts pipe-delimited prefixes from raw `Category.title`; Browse, Search, and Live expose group-first selection; the selected group set constrains category-picker rows; `SettingsScreen` hides detected groups per provider through `CategoryPrefixVisibilityStore`; and `LibraryFilterEngine` applies hidden/selected groups to local results.
- Current limitation: grouping depends entirely on the raw provider category title; normalized category metadata, language source configuration, and recommendation-facing selected-group filters are not implemented.

## User Experience

- Group selection appears before category selection in Browse, Search, and Live; selecting groups constrains the category picker to those groups.
- Unprefixed categories should remain visible under a fallback group.
- Users can hide provider prefix groups in Settings, and those provider-scoped choices apply across Browse, Search, Live, and For You.
- Language grouping should be configurable separately from raw provider category names when enough metadata exists.

## Data and State

- Current grouping source: `Category.title`.
- Current parser: pipe-delimited title pattern, where the first pipe segment becomes the group key.
- Current browse/search/live state: selected category and selected category-group keys narrow local `Media` results. A category is cleared if a later group selection excludes its group, while an empty group selection keeps any valid category.
- Prefix visibility is persisted per provider in the local `category_prefix_visibility` table and invalidated through the revisioned `CategoryPrefixVisibilityStore` cache.

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

- Recommendation surfaces apply provider-hidden groups but do not expose interactive selected-group filters.
- The current regex is intentionally narrow; normalized provider-agnostic grouping metadata and language-source configuration remain planned.

## Notes for Agents

- Do not hardcode one provider's category naming convention as a universal rule without keeping raw category titles intact.
- If prefix filtering is implemented, update `docs/filters-and-sorting.md`, `docs/search.md`, and `docs/for-you.md` because prefix visibility affects those features too.
- Be explicit about whether a new filter uses raw provider category title, normalized prefix, language code, or user preference state.
