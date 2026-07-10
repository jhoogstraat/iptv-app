# Feature: Favorites

## Purpose

Favorites lets users mark movies, series, channels, and playable items they care about and retrieve them from a dedicated library surface, search, details, For You, and player controls.

## Status

- Target state: favorite state is provider-scoped, persisted locally, visible across relevant surfaces, and available to local discovery/search surfaces.
- Implementation status (reviewed 2026-07-10): Provider-scoped `favorites` rows persist in SQLiteData with media type/source ID and display snapshots. `FavoriteStore` reports committed mutation outcomes and joins current catalog/category metadata when available. `FavoritesScreen` is live with adaptive scope controls plus platform-native remove actions for touch, pointer, keyboard, and tvOS focus; details, player, browse, search, and For You observe the same state.

## User Experience

- Users can add or remove a favorite from detail screens and the player.
- Favorites tab lists all favorited content with useful grouping/filtering.
- Favorite state appears consistently on browse tiles, details, search results, player controls, and For You where applicable.
- Removing a favorite updates all visible surfaces without app restart.
- Empty Favorites shows a clear empty state.

## Data and State

- `Favorite` stores provider ID, media type, source ID, title snapshot, artwork URL, category ID/title snapshot, created timestamp, and updated timestamp.
- Favorite records reference local `Media` by the stable provider-local content key (`mediaType` + `sourceID`) when the row is still present; unavailable favorites keep their snapshot for explicit UI states.
- Favorite writes bump `FavoriteStore.revisionKey` for surfaces that read synchronously, while SQLiteData queries keep loaded detail/search/browse/favorites screens fresh.
- Search, Browse, For You, detail screens, and player controls consume the persisted store; no remote favorite or recommendation sync exists.

## Key Files

- `iptv/Model/Database/Schema.swift`
- `iptv/UI/Screens/FavoritesScreen.swift`
- `iptv/UI/ContentView.swift`
- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Views/EpisodeDetailTile.swift`
- `iptv/Player/PlayerView.swift`
- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/UI/Screens/ForYouScreen.swift`

## Target Acceptance Criteria

- Favorite add/remove persists locally and is provider-scoped.
- Favorites tab renders persisted favorites from local state.
- Player and detail favorite buttons reflect the same persisted state.
- Favorite changes are immediately reflected in search/recommendation surfaces that are loaded.
- Deleting or changing provider state does not show stale favorites for another provider.
- Empty, loading, and unavailable states are explicit.

## Current Gaps / Planned Work

- Live-channel favorites remain out of scope until Live TV is implemented.
- Full-text favorite indexing and remote/provider sync are not implemented; current search reflects favorites as local badges on catalog results.
- Downloads and profiles are deferred, so favorite keys are provider-scoped but not profile-scoped.

## Notes for Agents

- Do not ship favorites as view-local state. The feature is only useful when persisted and shared.
- Update player, detail, search, and For You docs when favorite state becomes a real cross-surface dependency.
- Keep provider isolation explicit in the data model.
