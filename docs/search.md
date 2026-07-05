# Feature: Search

## Purpose

Search helps users find local library items quickly across synced Movies and Series, with scoped search inside browse screens and a global Search tab for cross-library discovery.

## Status

- Target state: scoped search works inside Movies and Series; global Search queries Movies and Series together; filters and sorting are available from the global surface; results are provider-scoped and backed by local data/indexes.
- Current implementation: global `SearchScreen` is a placeholder. The only active search behavior is `BrowseScreen.searchable`, which filters titles inside the selected category through the local `Media` query.
- Existing planning docs: `docs/search-implementation-spec.md` and `docs/library-search-spec.md` describe prior planned search architecture; this feature doc is the canonical cross-run target summary.

## User Experience

- Movies scoped search searches movies only.
- Series scoped search searches series only.
- Empty scoped query keeps category browsing visible.
- Global Search tab supports text query, scope selection, filter controls, active filter chips, and results.
- Search should clearly indicate whether results are complete, indexing, or partial.
- Tapping a result navigates to the appropriate detail destination.

## Data and State

- Current query source: local `Media.title.contains(filter)` in selected category.
- Target query source: provider-scoped local search index or local database query over Movies and Series.
- Target result fields: media identity, scope, title, artwork, rating, category/group, matched fields, and deterministic score/sort keys.
- Target filters: scope, group/prefix, rating range/min rating, genre, language, added recency, audio language, subtitle language when metadata exists.
- Target sorting: relevance, newest, rating, title, and deterministic tie-breakers.

## Key Files

- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/ContentView.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`
- `docs/search-implementation-spec.md`
- `docs/library-search-spec.md`

## Target Acceptance Criteria

- Global Search tab returns Movies and Series results from local state.
- Movies scoped search never returns series.
- Series scoped search never returns movies.
- Search results never leak across providers.
- Filters combine predictably and match `docs/filters-and-sorting.md` semantics.
- Search still returns partial indexed data with visible status if background indexing is incomplete.
- Query failures keep the last successful results visible with a retry affordance.
- Result navigation opens the correct detail surface.

## Current Gaps / Planned Work

- `SearchScreen` currently renders `ContentUnavailableView("Search not yet implemented")`.
- No search index store or orchestrator exists in the current file tree.
- Browse scoped search is category-scoped only, not full Movies/Series scoped search.
- No filter chips, sort controls, indexing progress, or global results UI exists.
- Current schema lacks many fields needed for advanced search filters.
- Favorites and continue watching are not currently searchable local entities.

## Notes for Agents

- Search is one feature even though it touches browse, global tab UI, local indexing, filters, details, and provider isolation.
- Prefer a local index/query layer over querying Xtream from the UI.
- Before implementing search contracts, reconcile this feature doc with the older search specs and update or retire stale details.
