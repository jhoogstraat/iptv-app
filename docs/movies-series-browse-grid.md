# Feature: Movies and Series Browse Grid

## Purpose

Movies and Series browse gives users fast local category navigation and poster-grid browsing for synced VOD and series content.

## Status

- Target state: Movies and Series share one robust browse implementation with local category selection, local search/filter/sort, adaptive poster grids, skeleton loading only during real loading, detail navigation, and lazy category hydration.
- Implementation status (reviewed 2026-07-10): Implemented for the active P1 Library UX path. `BrowseScreen(type:)` backs both Movies and Series, fetches local categories by `MediaType`, exposes shared filters/search/sorts, lazily hydrates selected unhydrated categories, shows explicit unhydrated/loading/empty/failed states, and renders local `Media` in an adaptive poster grid. Grid items navigate to `MediaDetailDestination`; the `SessionGuard` around each owning navigation stack supplies the same session to pushed details.
- Current gap: initial browse can span all visible categories; when only part of the catalog is hydrated, Browse shows a partial-local-coverage notice instead of pretending results are complete.

## User Experience

- Movies tab shows movie categories and movie posters.
- Series tab shows series categories and series posters.
- The navigation title reflects the selected category, falling back to Movies or Series.
- The horizontal filter bar presents Group before Category; selected groups constrain the category menu while preserving deterministic grouping order.
- Search field filters the selected category by title.
- Grid tiles use equal-width adaptive columns that fill the available horizontal axis, preserve the 2:3 poster ratio, show fallback title artwork on image failure, and use the same column strategy for loading skeletons.

## Data and State

- `BrowseScreen.type` controls whether categories are movie or series categories.
- `@FetchAll(Category.where { $0.type.eq(type) })` supplies categories.
- `selectedCategoryID` is optional; when unset, the grid spans all visible categories for the current media type.
- `searchText` is normalized through `LibraryQueryNormalizer` before in-memory matching, so scoped browse and global search share trim/lowercase/diacritic-fold/whitespace-collapse semantics.
- `BrowseSort.title`, `.newest`, and `.rating` are applied by `LibraryFilterEngine`.
- `CoverGridSection` snapshots the already-fetched local `Media`, categories, filter state, hidden groups, and query, computes the shared filter/sort result off the main actor, retains the previous grid while a newer request runs, and animates only the latest completed result into the grid. The task performs no SQLite or remote work.
- `Category.updatedAt == nil` triggers `session.update(type, in: category.id)`.

## Key Files

- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/ContentView.swift`
- `iptv/UI/SessionGuard.swift`
- `iptv/State/Session.swift`
- `iptv/State/SyncManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Views/EpisodeDetailTile.swift`

## Target Acceptance Criteria

- Movies and Series use the same browse implementation without divergent behavior.
- Browse reads from local `Category` and `Media` rows.
- Selecting an unhydrated category fetches and persists that category's media exactly through session/sync infrastructure.
- Empty category/provider states are explicit and non-crashing.
- Poster and skeleton grids use the same adaptive minimum-width columns, distribute remaining horizontal width evenly, and avoid fixed device assumptions or unexplained trailing voids.
- Tapping a movie routes to movie detail; tapping a series item routes to the appropriate series/episode detail experience.
- Search, filters, and sorting do not query remote APIs directly.

## Current Gaps / Planned Work

- Current search is title-only and does not use a full-text index or relevance scoring.
- Metadata-backed filters such as genre, release period, country, and added date are not exposed until the UI can prove those fields are populated enough for honest filtering.
- Favorite and download affordances on detail surfaces are not persisted yet.
- There is no row-level provider isolation for catalog tables beyond the single active-provider reset model.

## Notes for Agents

- Keep Movies and Series unified unless a product requirement truly differs by media type.
- When adding filter/sort behavior, prefer extending the local query/index rather than fetching remote data from the view.
- If detail navigation is added, update `app-navigation.md`, `media-details.md`, and `video-player.md` when play actions are affected.
