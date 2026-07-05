# Feature: Media Details

## Purpose

Media Details provides the focused destination for a selected movie or series item, showing artwork, metadata, actions, and playback entry points from local library state.

## Status

- Target state: browse/search/recommendation/favorites items route to a detail screen that displays local metadata, supports play/favorite/download actions, and bridges to the shared player.
- Current implementation: `MovieDetailScreen` exists and renders movie artwork, title, rating metadata, placeholder about text, and local state for play errors. Browse grid item navigation currently points to a not-implemented placeholder, so the detail screen is not wired from browse.
- Series detail exists only as `EpisodeDetailTile`/planned destination intent rather than a complete series detail flow.

## User Experience

- Tapping a movie opens movie details with poster artwork, title, rating, description/metadata, and actions.
- Tapping a series item opens an appropriate series or episode detail path.
- Details should expose Play, Favorite, Download, and related metadata when implemented.
- Failed artwork loads should degrade gracefully.
- Playback errors from a detail play action should be visible and recoverable.

## Data and State

- Current detail input: local `Media` row.
- Current available fields: title, cover URL, rating, source ID, media type, category ID, TMDB ID.
- Target fields: description, year, duration, cast/crew where available, genres, language, added date, trailer, episodes/seasons, favorite state, download state, watch progress, and playback URL resolution metadata.
- Player action should call `Player.load` after resolving a playable URL/source.

## Key Files

- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Views/EpisodeDetailTile.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/State/Player.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`

## Target Acceptance Criteria

- Browse/search/recommendation/favorite routes open the correct detail destination.
- Detail screens render from local persisted data and view state.
- Movie and series detail paths do not share incorrect assumptions about episodes or playback URLs.
- Play action resolves a playable source and launches the shared player.
- Favorite and download actions update their persisted feature state when those features are implemented.
- Missing metadata produces clear fallback UI instead of placeholder copy in completed paths.

## Current Gaps / Planned Work

- Browse tile navigation is not wired to `MovieDetailScreen`.
- `MovieDetailScreen` does not currently perform playback URL resolution.
- `Player.playbackURL(for:)` throws missing URL.
- Series detail is incomplete.
- Current schema lacks rich detail metadata and watch/favorite/download state.
- Placeholder about text should be replaced with provider/detail metadata when available.

## Notes for Agents

- Detail screens are a bridge between browse/search/recommendations and player/favorites/downloads. Update all affected feature docs when changing detail actions.
- Avoid remote detail fetching directly in the view unless the result is persisted or explicitly scoped as detail enrichment.
- Keep movie and series routing explicit to avoid accidentally treating series rows as playable movie streams.
