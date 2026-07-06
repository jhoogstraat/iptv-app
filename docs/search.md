# Feature: Search

## Purpose

Search helps users find local library items quickly across synced Movies and Series, with scoped search inside browse screens and a global Search tab for cross-library discovery.

## Status

- Target state: scoped search works inside Movies and Series; global Search queries Movies and Series together; filters and sorting are available from the global surface; results are provider-scoped and backed by local data/indexes when direct local queries no longer meet measured needs.
- Implementation status (reviewed 2026-07-06): Global `SearchScreen` is live in the Search tab, queries local Movies and Series from SQLiteData, supports text search, scope selection, shared category/group/minimum-rating filters, prefix visibility, deterministic title/newest/rating sorts, explicit partial-local-coverage states, and navigation to `MediaDetailDestination`. Scoped Browse search and global Search both use `LibraryQueryNormalizer` plus `LibraryFilterEngine`.
- Existing planning docs: `docs/search-implementation-spec.md` and `docs/library-search-spec.md` describe older planned indexed-search architecture; the current Library UX plan keeps direct local queries as the active implementation until measured need proves otherwise.

## User Experience

- Movies scoped search searches movies only.
- Series scoped search searches series only.
- Empty scoped query keeps category browsing visible.
- Global Search tab supports text query, scope selection, filter controls, active filter chips, and results.
- Search should clearly indicate whether results are complete, indexing, or partial.
- Tapping a result navigates to the appropriate detail destination.

## Data and State

- Current global query source: local `Media` rows for Movies and Series, filtered by normalized title text, scope, category/group visibility, minimum rating, and sort.
- Current scoped query source: `BrowseScreen` fetches local `Media` by media type, then applies the same normalized title query and shared filter state.
- Target result fields: media identity, scope, title, artwork, rating, category/group, matched title, and deterministic sort keys.
- Target filters: scope, group/prefix, rating range/min rating, plus genre, country/language, added recency, audio language, and subtitle language only when those fields are populated locally and exposed honestly.
- Target sorting: relevance when a future index exists, plus newest, rating, title, and deterministic tie-breakers.

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

- No dedicated full-text search index or relevance scoring exists; current global search filters local `Media.title` with shared normalization.
- Query failures/retry affordances are not represented because the current implementation reads directly from local tables.
- Search is single-active-library scoped rather than row-level provider scoped because `media`/`categories` lack provider columns.
- Rich metadata is now persisted for detail paths when Xtream list/detail DTOs expose it, but Search does not expose genre/language/recency filters until the local population contract and UI are complete.
- Favorites and continue watching are not currently searchable local entities.

## Notes for Agents

- Search is one feature even though it touches browse, global tab UI, local indexing, filters, details, and provider isolation.
- Prefer a local index/query layer over querying Xtream from the UI.
- Before implementing search contracts, reconcile this feature doc with the older search specs and update or retire stale details.
