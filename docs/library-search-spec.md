# Library and Search Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: P1 (next milestone after advanced player)

## Objective
Deliver a usable library and discovery experience with scoped and global search across VOD and series.

## In Scope
- Replace Search placeholder tab with functional Search screen.
- Scoped search inside Movies and Series screens.
- Global search across Movies + Series.
- Filter and sort controls in Global Search:
  - Scope (`All`, `Movies`, `Series`)
  - Rating range
  - Genre
  - Language
  - Added recency window
  - Sort (`Relevance`, `Newest`, `Rating`, `Title`).
- Search indexing progress indicator.
- Library surfaces:
  - Favorites list.
  - Continue watching list (read from watch activity).

## Out of Scope
- Live TV search.
- Semantic/vector search.
- Server-side query APIs beyond existing provider endpoints.

## UX Requirements
- Empty query in scoped search keeps existing category rails visible.
- Non-empty query shows ranked result section above category rails.
- Global search always provides a clear provider-scoped status:
  - fully indexed
  - indexing in progress
  - partial results.

## Architecture

## New modules
- `iptv/Model/Search/SearchIndexStore.swift`
- `iptv/Model/Search/SearchOrchestrator.swift`
- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/UI/Screens/SearchScreenViewModel.swift`

## Core contracts
- `SearchQuery`
  - text, scope, filters, sort.
- `SearchResultItem`
  - video reference, scope, score, matched fields.
- `SearchIndexProgress`
  - indexed categories, total categories, scope.

## Catalog integration
- Index updates triggered after successful catalog stream fetches.
- Index scoped by provider fingerprint.
- Index reset on provider config change.

## Ranking and Matching
- Normalize query: lowercase, trim, collapse whitespace, fold diacritics.
- Match fields:
  - title prefix
  - title contains
  - category name
  - language
  - genre.
- Tie-break order:
  - score desc
  - rating desc
  - added date desc
  - title asc
  - id asc.

## Favorites Integration
- Favorites must appear in Library and be searchable.
- Favorite state changes should update search results without requiring app restart.

## Failure Handling
- Indexing errors are non-fatal.
- Search still returns indexed subset with status indicating partial coverage.
- Query errors should not clear last successful results.

## Testing

## Unit
- Search normalization and matching logic.
- Filter semantics (AND across groups, OR within groups).
- Provider isolation in index store.
- Sorting and tie-break correctness.

## Integration
- Catalog fetch updates search index.
- Provider change clears and rebuilds index.
- Favorite add/remove updates index visibility.

## UI
- Scoped search behavior in Movies and Series.
- Global filter panel interactions.
- Progress state rendering during indexing.

## Acceptance Criteria
- Search tab returns results for Movies and Series with filters and sorting.
- Scoped search works in each content screen.
- Favorites and continue watching are visible library entities and discoverable through search.

