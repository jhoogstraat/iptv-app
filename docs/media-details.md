# Feature: Media Details

## Purpose

Media Details provides the focused destination for a selected movie or series item, showing artwork, metadata, actions, and playback entry points from local library state.

## Status

- Target state: browse/search/recommendation/favorites items route to a detail screen that displays local metadata, supports play/resume/download for playable rows, and bridges to the shared player; favorite and download controls persist through profile/provider-scoped stores.
- Implementation status: `MediaDetailDestination` routes movies, series, episodes, and live states explicitly from Browse, Search, Favorites, and For You. Movie and series screens share adaptive hero/backdrop presentation, visible failure/retry enrichment state, profile-scoped favorite/resume state, working trailer links, source selection, downloads, native navigation chrome, and shared full-window playback entry. Each screen presents its synopsis once in the hero and omits redundant media-type and episode-selection actions. Movie actions use a content-fitting horizontal layout with a vertical fallback for compact widths, localization, and larger text.
- Series detail keeps its own Episodes/Details content and season selection. Selecting a concrete episode row calls the shared player directly with full-window presentation and surfaces terminal resolution/backend errors in the series detail; standalone `EpisodeDetailTile` routes remain available from other surfaces. `SyncManager.enrichDetails` single-flights detail requests, rejects stale provider ownership, reconciles seasons/episodes, and preserves the last good local snapshot when enrichment fails.

## User Experience

- Tapping a movie opens movie details with poster artwork, title, rating, description/metadata, and actions.
- Tapping a series item opens series detail; tapping a concrete episode row there launches that episode in the shared full-window player without an intermediate episode-detail screen.
- Details should expose Play/Resume, Favorite, Download, and related metadata when implemented.
- Failed artwork loads should degrade gracefully.
- Playback errors from a detail play action should be visible and recoverable.
- Detail enrichment failures remain visible above saved metadata and provide a Retry action.
- While initial detail enrichment is running, the metadata card is already visible in its final horizontal position and contains a progress indicator instead of placeholder values. It stays top-anchored and expands downward with an opacity reveal when metadata becomes available. Its content is width-constrained to the visible detail column so long values wrap instead of forcing iPad portrait overflow.

### UI Direction

- Model the detail screen after modern streaming apps such as Netflix and Disney+: the first viewport should be a cinematic, full-width hero photo/backdrop with the interface layered on top rather than a separate header card.
- The hero image should occupy the top of the screen and extend behind the safe-area/top chrome where platform conventions allow. Use dark gradient scrims and blur/material layers so titles, metadata, and controls stay readable over bright or busy artwork.
- Top-level navigation controls (back/close, overflow or source menus when needed) should float above the hero image. They should remain visually lightweight and legible, with enough touch target space for iPhone and iPad.
- The primary content overlay should include the title, genre/category, rating/year/runtime or season metadata, a concise synopsis, and primary actions such as Play/Resume, Favorite, Mute/Trailer when available, and Other Sources.
- Scrolling should transition from the immersive hero into deeper detail content. As the user scrolls, the hero may dim/collapse while tab or segment controls and detail sections become the focus.
- Series details should expose episode-focused navigation below the hero: tabs such as Episodes and Details, season selection, and vertically scrollable episode rows with thumbnail, season/episode code, title, synopsis preview, and release date.
- Movie details should use the same hero-first structure but replace episode navigation with movie-specific sections such as synopsis, metadata, related items, cast/crew, trailer, and source/download status when available.
- Missing artwork should keep the layout stable by using a dark branded placeholder, gradient background, or poster fallback rather than shrinking the hero area.

## Data and State

- Current detail input: local `Media` row, refreshed from SQLiteData while the detail screen is open.
- Current persisted fields: title, cover/backdrop URL, rating, source ID, media type, category ID, TMDB ID, synopsis/plot, release date/year, runtime, genre, cast, director, trailer, added date, country when exposed by Xtream DTOs, parent-series/season/episode linkage, and movie/episode container extension.
- Series seasons are stored in `SeriesSeason`; playable episodes are stored as `Media(type: .episode)` rows linked by `parentSeriesID`.
- Player actions call `Player.load` after resolving a playable URL/source. A concrete series episode row loads its `.episode` directly with full-window presentation; standalone episode detail routes use the same full-window play contract. Series collection rows remain explicitly non-playable.
- Movie and episode detail screens query active-profile/provider `WatchActivity` rows to label Play vs Resume. Favorite and download state use the same profile/provider content boundary.

## Key Files

- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Screens/SeriesDetailScreen.swift`
- `iptv/UI/Screens/MediaDetailDestination.swift`
- `iptv/UI/Views/EpisodeDetailTile.swift`
- `iptv/UI/Views/MediaDetailSupport.swift`
- `iptv/UI/Views/DetailPresentation.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/State/Player.swift`
- `iptv/Player/MediaPlaybackSourceResolver.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`

## Target Acceptance Criteria

- Browse/search/recommendation/favorite routes open the correct detail destination.
- Detail screens render from local persisted data and view state.
- Movie and series detail paths do not share incorrect assumptions about episodes or playback URLs.
- Play action resolves a playable source and launches the shared player.
- Sources lets users prefer a verified local asset or explicitly bypass it for the provider stream. Trailer opens only when the provider supplied a usable URL or YouTube identifier.
- Playable movie and episode details show Resume/progress only for unfinished meaningful watch activity; completed or too-short progress starts from zero.
- Favorite actions update provider-scoped persisted state; download actions remain explicit unavailable affordances until downloads are implemented.
- Missing metadata produces clear fallback UI instead of placeholder copy in completed paths.
- The detail UI uses a hero-first streaming layout: large backdrop/photo at the top, controls and core metadata layered over it, and additional information revealed through scrollable sections below.
- Series detail screens expose episode tabs, season selection, and episode rows below the hero.

## Current Gaps / Planned Work

- Recommendation and favorites surfaces now route local `Media` rows into the same detail destination; unavailable favorite snapshots stay in the Favorites tab until the catalog row exists again.
- Download actions are still explicit unavailable/disabled affordances until their persisted feature state is implemented.
- Audio language, subtitle language, and profile/preference metadata are not exposed because current Xtream catalog/detail DTOs do not provide reliable local fields for those filters.
- Missing provider metadata renders as explicit unavailable copy in the synopsis, metadata grid, and episode rows instead of fake placeholder values.

## Notes for Agents

- Detail screens are a bridge between browse/search/recommendations and player/favorites/downloads. Update all affected feature docs when changing detail actions.
- Avoid remote detail fetching directly in the view unless the result is persisted or explicitly scoped as detail enrichment.
- Keep movie and series routing explicit to avoid accidentally treating series rows as playable movie streams.
