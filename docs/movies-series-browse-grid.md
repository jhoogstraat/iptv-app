# Feature: Movies and Series Browse Grid

## Purpose

Movies and Series browse gives users fast local category navigation and poster-grid browsing for synced VOD and series content.

## Status

- Target state: Movies and Series share one robust browse implementation with local category selection, local search/filter/sort, adaptive poster grids, skeleton loading, detail navigation, and lazy category hydration.
- Implementation status (reviewed 2026-07-05): Partial. `BrowseScreen(type:)` backs both Movies and Series, fetches local categories by `MediaType`, exposes shared filters/search/sorts, lazily hydrates selected unhydrated categories, and renders local `Media` in an adaptive poster grid. Grid items now navigate to `MediaDetailDestination`.
- Current gap: initial browse has no selected category by default and therefore spans all visible categories; empty `media` still renders skeleton tiles, which can conflate loading and truly empty categories.

## User Experience

- Movies tab shows movie categories and movie posters.
- Series tab shows series categories and series posters.
- The navigation title reflects the selected category, falling back to Movies or Series.
- Toolbar category menu groups categories by prefix and lets users switch category with animation.
- Search field filters the selected category by title.
- Grid tiles show poster artwork when available, fallback title artwork on image failure, skeleton placeholders while loading, and optional rating badges.

## Data and State

- `BrowseScreen.type` controls whether categories are movie or series categories.
- `@FetchAll(Category.where { $0.type.eq(type) })` supplies categories.
- `selectedCategoryID` is optional; when unset, the grid spans all visible categories for the current media type.
- `searchText` filters local media titles for the current media type before filter-state narrowing.
- `BrowseSort.title`, `.newest`, and `.rating` are applied by `LibraryFilterEngine`.
- `CoverGridSection` fetches local `Media` rows for the current type and title filter, then applies category/group/rating/sort filters.
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
- Poster grid adapts to available width and avoids fixed device assumptions.
- Tapping a movie routes to movie detail; tapping a series item routes to the appropriate series/episode detail experience.
- Search, filters, and sorting do not query remote APIs directly.

## Current Gaps / Planned Work

- Empty `media` currently renders skeleton tiles, which may conflate loading and truly empty categories.
- Current search is title-only and does not use a full-text index or relevance scoring.
- The schema lacks metadata needed for richer browse filters such as year, genre, language, audio language, subtitle language, and added date.
- Series detail routing exists, but episode sync/persistence is incomplete.
- Favorite and download affordances on detail surfaces are not persisted yet.
- There is no row-level provider isolation for catalog tables.

## Notes for Agents

- Keep Movies and Series unified unless a product requirement truly differs by media type.
- When adding filter/sort behavior, prefer extending the local query/index rather than fetching remote data from the view.
- If detail navigation is added, update `app-navigation.md`, `media-details.md`, and `video-player.md` when play actions are affected.
