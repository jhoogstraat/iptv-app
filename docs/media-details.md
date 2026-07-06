# Feature: Media Details

## Purpose

Media Details provides the focused destination for a selected movie or series item, showing artwork, metadata, actions, and playback entry points from local library state.

## Status

- Target state: browse/search/recommendation/favorites items route to a detail screen that displays local metadata, supports play/resume for playable rows, and bridges to the shared player; favorite/download controls stay explicit unsupported states until their feature stores exist.
- Implementation status (reviewed 2026-07-06): `MediaDetailDestination` routes movies, series, episodes, and live unsupported states explicitly. Browse grids, search results, and reusable media rows open details instead of generic placeholders. `MovieDetailScreen` uses a hero-first streaming layout, refreshes Xtream VOD detail metadata through `Session`/`SyncManager`, persists the result locally, shows provider-scoped resume state from `WatchActivity`, and starts playback through `Player.load`, which resolves movie URLs through the active Xtream provider and synced source ID/container extension.
- Series detail has its own hero-first route with Episodes/Details tabs, a season selector, local episode rows, and explicit unavailable copy when no episode rows are persisted. `SyncManager.enrichDetails` uses the Xtream series detail endpoint to persist series metadata, seasons, and episode `Media` rows linked to their parent series; episode detail rows show resume progress from the same provider-scoped watch-activity table.

## User Experience

- Tapping a movie opens movie details with poster artwork, title, rating, description/metadata, and actions.
- Tapping a series item opens an appropriate series or episode detail path.
- Details should expose Play/Resume, Favorite, Download, and related metadata when implemented.
- Failed artwork loads should degrade gracefully.
- Playback errors from a detail play action should be visible and recoverable.

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
- Player action calls `Player.load` after resolving a playable URL/source. Series collection rows remain explicitly non-playable.
- Movie and episode detail screens query provider-scoped `WatchActivity` rows by active provider ID, media type, and source ID to label Play vs Resume and show progress/remaining time.

## Key Files

- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Views/EpisodeDetailTile.swift`
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
- Playable movie and episode details show Resume/progress only for unfinished meaningful watch activity; completed or too-short progress starts from zero.
- Favorite and download actions update their persisted feature state when those features are implemented.
- Missing metadata produces clear fallback UI instead of placeholder copy in completed paths.
- The detail UI uses a hero-first streaming layout: large backdrop/photo at the top, controls and core metadata layered over it, and additional information revealed through scrollable sections below.
- Series detail screens expose episode tabs, season selection, and episode rows below the hero.

## Current Gaps / Planned Work

- Recommendation and favorites surfaces are still placeholders, so their detail routing will become active when those surfaces render local `Media` rows.
- Favorite and download actions are visible as explicit unavailable/disabled affordances until their persisted feature state is implemented.
- Audio language, subtitle language, and profile/preference metadata are not exposed because current Xtream catalog/detail DTOs do not provide reliable local fields for those filters.
- Missing provider metadata renders as explicit unavailable copy in the synopsis, metadata grid, and episode rows instead of fake placeholder values.

## Notes for Agents

- Detail screens are a bridge between browse/search/recommendations and player/favorites/downloads. Update all affected feature docs when changing detail actions.
- Avoid remote detail fetching directly in the view unless the result is persisted or explicitly scoped as detail enrichment.
- Keep movie and series routing explicit to avoid accidentally treating series rows as playable movie streams.
