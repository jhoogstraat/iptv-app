# Feature: Movies and Series Browse Grid

## Purpose

Movies and Series browse gives users fast local category navigation and poster-grid browsing for synced VOD and series content.

## Status

- Target state: Movies and Series share one robust browse implementation with native category navigation, local search/filter/sort inside each category, adaptive poster grids, skeleton loading only during real loading, detail navigation, and lazy category hydration.
- Implementation status (reviewed 2026-07-18): Implemented for the active P1 Library UX path. `BrowseScreen(type:)` backs both Movies and Series and opens on a sectioned, searchable category list grouped by detected prefix. Category rows are native `NavigationLink` values that push `BrowseCategoryScreen`; the landing screen owns only category Group/search state, while each pushed screen independently owns media rating/search/sort state. Swiping a category row reloads its media through the existing detached hydration path; its subtitle displays a compact activity indicator while that refresh is running. The destination lazily hydrates its category off the main actor, shows shimmer tiles throughout hydration plus explicit empty/failed states, and observes only that category's local `Media`. A compact grouped-count query supplies landing-row status. Query changes are debounced and run in a cancellation-propagating background worker keyed by compact criteria/catalog revision state. Grid items navigate to `MediaDetailDestination`; the `SessionGuard` around each owning navigation stack supplies the same session to pushed details.
- Current gap: media filters remain limited to rating and deterministic sorting until broader metadata coverage can support additional truthful filters.

## User Experience

- Movies tab shows movie categories and movie posters.
- Series tab shows series categories and series posters.
- The landing navigation title is Movies or Series. A pushed media screen uses the category title.
- Movies and Series open on a sectioned list whose section titles are category groups and whose rows are categories. Selecting a row pushes that category through native SwiftUI navigation, so the system back button and interactive back swipe return to the category list.
- Category is navigation context, never an active filter or filter pill. The landing bar filters category rows by Group; after navigation, a separate media bar exposes Rating and Sort.
- Search field filters the selected category by title.
- Grid tiles use equal-width adaptive columns that fill the available horizontal axis, preserve the 2:3 poster ratio, show fallback title artwork on image failure, and use the same column strategy for loading skeletons.

## Data and State

- `BrowseScreen.type` controls whether categories are movie or series categories.
- `@FetchAll(Category.where { $0.type.eq(type) })` supplies categories.
- `BrowseScreen` owns landing-only `selectedGroupKeys` and category search state. `BrowseCategoryScreen` receives a concrete `Category` from navigation, initializes its database observation with that category and media type already applied, and owns its own media search, rating, and sort state. Its presentation request also carries the category ID as a defensive constraint, so an initial or stale unscoped snapshot cannot expose media from another category.
- Category and media search text are separately normalized through `LibraryQueryNormalizer`; landing search matches category titles, while destination search matches media titles only inside the navigated category.
- `BrowseSort.title`, `.newest`, and `.rating` are applied by `LibraryFilterEngine`.
- `CoverGridSection` snapshots the already-fetched local `Media`, categories, filter state, hidden groups, and query, computes the shared filter/sort result off the main actor, and retains the previous grid while a newer request runs. SwiftUI compares a compact `LibraryFilterTaskID`; catalog arrays are not part of task identity. Cancellation propagates into the worker, and the latest bulk result is committed without a full-grid animation. The task performs no SQLite or remote work.
- `Category.updatedAt == nil` triggers `session.update(type, in: category.id)`.
- Category row counts are observed through a grouped aggregate query, avoiding full-catalog reductions and equality comparisons on the main actor.

## Key Files

- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Views/LibraryCategoryList.swift`
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
- A category destination never presents media from another category, including while its first hydration changes the local catalog.
- Category rows use native navigation, do not increment the active-filter count, and support the platform back gesture.
- Category rows offer a trailing swipe action that reloads their media without blocking the landing list; the subtitle visibly indicates the in-progress refresh.
- Group state filters the category landing list but is not carried into the pushed media filter state.
- Selecting a large category remains interactive while provider decoding and reconciliation run away from the main actor, and the UI receives one committed catalog update.
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
