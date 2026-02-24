# For You Page

This document describes the implemented `For You` page in `iptv`, including:

- UI behavior
- data sources
- recommendation pipeline
- scoring/ranking algorithms
- persistence rules for watch activity

## Scope

`For You` is currently implemented for:

- VOD
- Series

Out of scope for this page version:

- Live recommendations
- Favorites recommendations
- Downloads recommendations
- Search-driven recommendations

## Entry Points

- UI screen: `iptv/UI/Screens/ForYouScreen.swift`
- View model/orchestration: `iptv/UI/Screens/ForYou/ForYouViewModel.swift`
- Recommendation provider contract: `iptv/Model/ForYou/RecommendationProvider.swift`
- Local algorithms: `iptv/Model/ForYou/LocalRecommendationRanker.swift`
- Watch history persistence: `iptv/Model/WatchActivity/WatchActivityStore.swift`
- Watch activity models: `iptv/Model/WatchActivity/WatchActivityModels.swift`

## UI Behavior

`ForYouScreen` has four states:

1. Missing provider config:
- shows configure CTA and opens `SettingsScreen`.

2. Loading:
- shows a spinner.

3. Failed:
- shows error and retry button.

4. Loaded:
- hero module (`ForYouHeroView`) when available.
- rail modules:
  - `Continue Watching` (`ContinueWatchingCardView`)
  - poster rails (`ForYouRailView`) for recommendation sections.

Navigation:

- VOD items open `MovieDetailScreen`.
- Series items open `EpisodeDetailTile`.

Hero actions:

- `Play`: resolves stream URL via `Catalog.resolveURL(for:)` and starts player.
- `Details`: opens detail destination for the same item.

## Data Sources

## Provider catalog

From `Catalog` + Xtream endpoints:

- VOD categories + streams
- Series categories + streams
- Stream metadata:
  - title
  - poster URL
  - content type
  - rating
  - `added` timestamp (when available)
- Poster image cache:
  - prefetches poster URLs for the active category window
  - stores image responses in `URLCache` with app-managed TTL (`Cache-Control: public, max-age=43200`)
  - shared cache capacity defaults to ~96 MB memory / 512 MB disk

Related code:

- `iptv/Model/Catalog.swift`
- `iptv/Model/Mapper.swift`
- `iptv/Model/Caching/StreamListCache.swift` (`CachedVideoDTO.added`)
- `iptv/Model/Caching/ImageCache.swift`

## Watch activity

From local disk storage:

- file: `Application Support/WatchActivity/watch_activity.json`
- keyed by provider fingerprint + content type + video id
- stores progress, duration, completion, and last played timestamp

Related code:

- `iptv/Model/WatchActivity/WatchActivityStore.swift`
- `iptv/Model/WatchActivity/WatchActivityModels.swift`

## Provider isolation

All watch records are filtered by provider fingerprint, generated from:

- `ProviderCacheFingerprint.make(from:)`

This prevents cross-provider recommendation leakage.

## Recommendation Pipeline

`ForYouViewModel.load(force:)` performs:

1. Guard provider configuration.
2. Fetch categories:
- VOD
- Series
3. Select category windows:
- first 8 VOD categories
- first 6 Series categories
4. Fetch streams for selected categories.
- category errors are logged and skipped (best-effort load).
5. Load watch records and filter by current provider fingerprint.
6. Build `RecommendationContext`.
7. Call recommendation provider (`LocalRecommendationProvider`).
8. Publish hero + sections.

## Local Recommendation Algorithms

Implemented in `LocalRecommendationRanker`.

### Candidate index

`buildCatalogIndex` creates:

- `videosByKey`: unique videos keyed by `contentType:id`
- `categoryNamesByKey`: normalized category names per video
- `categoryDensity`: category population counts

Normalization:

- category names are trimmed + lowercased.

### Continue Watching

Source: watch records only.

Filter:

- `isCompleted == false`
- `progressFraction >= 0.05`
- `progressFraction <= 0.95`

Sort:

- `lastPlayedAt` descending

Limit:

- 20 items

### Because You Watched

Excludes already watched video keys.

Per-candidate score:

- `overlapScore * 0.5`
- `languageScore * 0.2`
- `ratingScore * 0.2`
- `recencyScore * 0.1`

Where:

- `overlapScore` is weighted category overlap with recent watch history.
- `languageScore` is weighted language affinity from recent watch history.
- `ratingScore` is normalized rating (`rating / 10`, clamped to 0...1).
- `recencyScore` is normalized recency from `addedAtRaw`.

History window:

- up to 30 recent watch records.

Sort:

- score descending
- tie-breaker by title ascending, then id ascending

Limit:

- 24 items

### Trending on Your Provider

Per-candidate score:

- `normalizedRating * 0.5`
- `normalizedRecency * 0.3`
- `categoryDensityScore * 0.2`

Where:

- `categoryDensityScore` is max normalized density among candidate categories.

Sort:

- score descending
- tie-break by title, then id

Limit:

- 24 items

### Critically Acclaimed

Filter:

- `rating >= 7.5`

Sort:

- rating descending
- title ascending
- id ascending

Limit:

- 24 items

### New Additions

Filter:

- parsable `addedAtRaw` only

Date parsing supports:

- unix seconds / milliseconds
- `yyyy-MM-dd HH:mm:ss`
- `yyyy-MM-dd`
- `yyyyMMdd`
- `dd-MM-yyyy`

Sort:

- added date descending
- title ascending
- id ascending

Badge:

- forced `.isNew`

Limit:

- 24 items

### Binge-Worthy Series

Filter:

- `xtreamContentType == .series`
- `rating >= 7.0`

Base sort:

- rating descending
- title ascending
- id ascending

Diversity rule:

- max 4 selected items per normalized category bucket

Limit:

- 24 items

### Hero selection

Priority order:

1. first `Continue Watching`
2. first `Because You Watched`
3. first `Critically Acclaimed`
4. first `Trending`

## Section Assembly Rules

`LocalRecommendationProvider` composes sections in order:

1. Continue Watching (if not empty)
2. Because You Watched (if at least 8 items)
3. Trending (if at least 8 items)
4. Critically Acclaimed (if at least 8 items)
5. New Additions (if at least 8 items)
6. Binge-Worthy Series (if at least 8 items)

Deduplication:

- hero id is reserved first.
- each rail is deduplicated against already emitted ids.
- dedupe key: `contentType:id`.

## Watch Activity Write Rules

Player integration in `iptv/Model/Player.swift`:

- on playback progress events, write only when either:
  - time delta >= 10 seconds, or
  - progress delta >= 0.05
- on `ended`, mark item completed.

Completion threshold in record update:

- `progressFraction >= 0.98` => completed.

## Failure and Resilience

- Category fetch failures are non-fatal during `For You` load.
- Corrupt watch activity file is reset automatically.
- If no recommendations are available, UI shows:
  - "Not enough activity yet. Start watching to personalize this page."

## Extension Point for Remote Recommendations

`RecommendationProviding` allows replacement of the local engine.

- Current remote implementation (`RemoteRecommendationProvider`) is a stub.
- Future remote provider should emit the same `(hero, sections)` output contract.

## Test Coverage

Implemented tests:

- `iptvTests/LocalRecommendationProviderTests.swift`
  - section ordering
  - hero fallback behavior
  - small-rail suppression behavior

- `iptvTests/WatchActivityStoreTests.swift`
  - persistence roundtrip
  - completion and provider filtering
  - corrupt-file recovery
