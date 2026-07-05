# Feature: Media Details

## Purpose

Media Details provides the focused destination for a selected movie or series item, showing artwork, metadata, actions, and playback entry points from local library state.

## Status

- Target state: browse/search/recommendation/favorites items route to a detail screen that displays local metadata, supports play/favorite/download actions, and bridges to the shared player.
- Current implementation: `MediaDetailDestination` routes local movie and series rows to explicit detail paths. Browse grids, search results, and reusable media rails open details instead of placeholders. `MovieDetailScreen` uses a hero-first streaming layout and resolves movie playback through the shared `Player` using the active Xtream provider and the synced source ID.
- Series detail now has its own hero-first route with Episodes/Details tabs and a season selector shell, but the local schema does not yet persist seasons or episode rows for a selected series.

## User Experience

- Tapping a movie opens movie details with poster artwork, title, rating, description/metadata, and actions.
- Tapping a series item opens an appropriate series or episode detail path.
- Details should expose Play, Favorite, Download, and related metadata when implemented.
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

- Current detail input: local `Media` row.
- Current available fields: title, cover URL, rating, source ID, media type, category ID, TMDB ID.
- Target fields: description, year, duration, cast/crew where available, genres, language, added date, trailer, episodes/seasons, favorite state, download state, watch progress, and playback URL resolution metadata.
- Player action should call `Player.load` after resolving a playable URL/source.

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
- Favorite and download actions update their persisted feature state when those features are implemented.
- Missing metadata produces clear fallback UI instead of placeholder copy in completed paths.
- The detail UI uses a hero-first streaming layout: large backdrop/photo at the top, controls and core metadata layered over it, and additional information revealed through scrollable sections below.
- Series detail screens expose episode tabs, season selection, and episode rows below the hero.

## Current Gaps / Planned Work

- Recommendation and favorites surfaces are still placeholders, so their detail routing will become active when those surfaces render local `Media` rows.
- Series episode sync is incomplete; the series detail screen exposes the target Episodes/Details structure with a clear unavailable state instead of playable episode rows.
- Current schema lacks rich detail metadata, watch/favorite/download state, and movie container extensions for fully qualified playback URLs.
- Favorite and download actions are visible as detail affordances but are not persisted until their feature stores are migrated.
- Placeholder about text has been replaced by explicit unavailable metadata copy, but provider synopsis/year/runtime/cast fields are still not available locally.

## Notes for Agents

- Detail screens are a bridge between browse/search/recommendations and player/favorites/downloads. Update all affected feature docs when changing detail actions.
- Avoid remote detail fetching directly in the view unless the result is persisted or explicitly scoped as detail enrichment.
- Keep movie and series routing explicit to avoid accidentally treating series rows as playable movie streams.
