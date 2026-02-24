# Search Implementation Spec (AI-Ready)

## Status
- Version: v1
- Date: 2026-02-23
- Scope locked for implementation

## Objective
Implement search in two surfaces:
1. Scoped search inside each media screen:
- Movies screen searches movies only.
- Series screen searches series only.
2. Global Search tab:
- Searches across Movies + Series.
- Supports advanced filters and sort options.

The implementation must be provider-isolated and progressively improve result coverage via background indexing.

## Current Code Context
- Search tab is a placeholder in `iptv/ContentView.swift`.
- Movies/Series screens exist in `iptv/UI/Screens/MoviesScreen.swift`.
- Category row loading is in `iptv/UI/Views/VideoTileRow.swift`.
- Provider isolation key exists via `ProviderCacheFingerprint` in `iptv/Model/Caching/StreamListCache.swift`.
- Catalog stream loading exists in `iptv/Model/Catalog.swift`:
- `getVodStreams(in:force:)`
- `getSeriesStreams(in:force:)`

## In Scope (v1)
- Movies + Series search only.
- Scoped search in Movies and Series screens.
- New global Search screen with:
- Text query
- Scope filter (`All`, `Movies`, `Series`)
- Advanced filters:
- type
- rating range
- genre (multi)
- year range
- language (multi)
- recency (`Any`, `30d`, `90d`, `1y`)
- sort (`Relevance`, `Newest`, `Rating`, `Title`)
- Hybrid lazy indexing:
- Search immediately on indexed data.
- Continue indexing categories in background.
- Show indexing progress in global search.

## Out of Scope (v1)
- Live search.
- Favorites/downloads search.
- Server-side search API integration.
- Semantic/vector search.

## Required Architecture

### 1) Domain Types (new files under `iptv/Model/Search/`)
- `SearchMediaScope`
  - `.all`
  - `.movies`
  - `.series`
- `SearchSort`
  - `.relevance`
  - `.newestAdded`
  - `.ratingDesc`
  - `.titleAsc`
  - `.yearDesc`
- `SearchAddedWindow`
  - `.any`
  - `.days30`
  - `.days90`
  - `.year1`
- `SearchFilters`
  - `scope: SearchMediaScope` (secondary scope guard for filter panel)
  - `minRating: Double?`
  - `maxRating: Double?`
  - `genres: Set<String>`
  - `yearRange: ClosedRange<Int>?`
  - `languages: Set<String>`
  - `addedWindow: SearchAddedWindow`
- `SearchQuery`
  - `text: String`
  - `filters: SearchFilters`
  - `sort: SearchSort`
- `SearchResultItem`
  - `video: Video`
  - `scope: SearchMediaScope` (`movies` or `series`)
  - `score: Double` (used when sort is relevance)
  - `matchedFields: Set<SearchMatchedField>`
- `SearchMatchedField`
  - `.titlePrefix`
  - `.titleContains`
  - `.genre`
  - `.language`
  - `.category`

### 2) Index Store
- Add `SearchIndexStore` actor in `iptv/Model/Search/SearchIndexStore.swift`.
- Responsibilities:
  - Maintain provider-scoped in-memory index.
  - Upsert results from catalog stream loads.
  - Query with filters + sort.
  - Clear index on provider change/reset.
- Required API:
  - `upsert(videos: [Video], contentType: XtreamContentType, category: Category, providerFingerprint: String) async`
  - `query(_ query: SearchQuery, providerFingerprint: String) async -> [SearchResultItem]`
  - `progress(scope: SearchMediaScope, providerFingerprint: String) async -> SearchIndexProgress`
  - `clear(providerFingerprint: String) async`
  - `clearAll() async`

### 3) Index Coverage Tracking
- Add `SearchIndexProgress`:
  - `indexedCategories: Int`
  - `totalCategories: Int`
  - `scope: SearchMediaScope`
- Track indexed category IDs per scope and provider.

### 4) Search Orchestration
- Add `SearchOrchestrator` actor in `iptv/Model/Search/SearchOrchestrator.swift`.
- Responsibilities:
  - Manage background indexing tasks.
  - Provide async progress stream to UI.
  - Prevent duplicate index jobs per provider/scope/category.
- Required API:
  - `ensureCoverage(scope: SearchMediaScope, providerFingerprint: String) -> AsyncStream<SearchIndexProgress>`
  - `cancelAll(providerFingerprint: String)`

## Catalog Integration

## Required changes in `iptv/Model/Catalog.swift`
- Add dependencies:
  - `searchIndexStore: SearchIndexStore`
  - `searchOrchestrator: SearchOrchestrator`
- New methods:
  - `search(_ query: SearchQuery) async throws -> [SearchResultItem]`
  - `searchIndexProgress(scope: SearchMediaScope) async -> SearchIndexProgress`
  - `ensureSearchCoverage(scope: SearchMediaScope) -> AsyncStream<SearchIndexProgress>`
  - `clearSearchIndex() async`
- Hook indexing into existing stream loads:
  - after successful `getVodStreams`
  - after successful `getSeriesStreams`
- On `reset()` and provider revision change:
  - clear search index for old provider
  - cancel search orchestrator tasks

## UI Requirements

### 1) Scoped Search in Movies/Series
- File: `iptv/UI/Screens/MoviesScreen.swift`
- Add:
  - `@State private var queryText: String = ""`
  - `@State private var scopedResults: [SearchResultItem] = []`
  - debounced query task (`Task` cancellation on text change)
- Behavior:
  - Empty query:
    - existing category rows only.
  - Non-empty query:
    - show a top result section before category rows.
    - keep category rows visible below.
- Scope mapping:
  - Movies screen -> `SearchMediaScope.movies`
  - Series screen -> `SearchMediaScope.series`

### 2) Global Search Screen
- Add `iptv/UI/Screens/SearchScreen.swift`.
- Replace placeholder tab in `iptv/ContentView.swift` with `SearchScreen()`.
- Screen content:
  - searchable text field
  - scope segmented control (`All`, `Movies`, `Series`)
  - “Filters” button opening advanced filter sheet
  - active filter chips with remove action
  - result list/grid
  - indexing progress label when coverage incomplete
- Add `SearchScreenViewModel`:
  - debounced query + filter state
  - calls catalog search
  - listens to progress stream

## Query and Ranking Rules

### Text normalization
- Lowercase
- Trim whitespace
- Fold diacritics
- Collapse repeated spaces

### Match logic
- A result matches when:
  - title contains query text, or
  - query text matches normalized genre/language/category label
- Empty text means “filter-only mode” (results from filters + scope).

### Relevance score (when sort = relevance)
- `titlePrefix`: +100
- `titleContains`: +50
- `genre/category/language hit`: +20 each (max +40 total from metadata)
- `rating normalized (0...10)`: +0...10
- `recency bonus`: +0...5 (based on `addedAtRaw` when parseable)

Tie-break order:
1. score desc
2. rating desc
3. added date desc
4. title asc
5. id asc

### Filter semantics
- AND across filter groups.
- OR within a group (e.g. selected genres or selected languages).
- Missing metadata behavior:
  - if a filter requires a field and field is missing, exclude item.

## Performance Constraints
- Debounce: 250ms.
- Query p95 on indexed corpus: <= 200ms.
- Background indexing concurrency: max 2 categories at once.
- No main-actor blocking during ranking/filtering.

## Error Handling
- Category indexing failures are non-fatal.
- Search should still return partial indexed results.
- UI shows non-blocking status: “Partial results while indexing”.
- Query operation failures display retry affordance and keep previous successful results rendered.

## Test Specification

### Unit tests (`iptvTests/`)
- `SearchIndexStoreTests.swift`
  - provider isolation
  - upsert + dedupe
  - match rules
  - filter semantics
  - sort correctness
- `SearchOrchestratorTests.swift`
  - no duplicate jobs for same scope/category/provider
  - progress stream monotonic updates
- `CatalogSearchIntegrationTests.swift`
  - catalog stream fetch updates index
  - reset/provider change clears search data

### UI tests (`iptvUITests/`)
- Scoped search on Movies returns movies only.
- Scoped search on Series returns series only.
- Search tab renders and queries across both scopes.
- Filters apply and chips reflect active filters.
- Tapping result navigates to proper detail destination.

## Delivery Packages

### Package A: Search Foundation + Scoped Search
- Add domain types, index store, catalog hooks.
- Add scoped search UI in `MoviesScreen`.

### Package B: Global Search + Advanced Filters
- Add `SearchScreen`, filters sheet, sort, progress UI.
- Replace Search placeholder tab.

### Package C: Enhancements
- Recent searches (provider-scoped, local persistence).
- Saved filter presets.
- Query suggestions.

## Acceptance Criteria
- Movies scoped search never returns series.
- Series scoped search never returns movies.
- Global `All` returns combined Movies + Series.
- Advanced filters work in combination.
- Search index resets on provider change.
- Tests described above pass on CI/local.

