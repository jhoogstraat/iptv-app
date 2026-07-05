# Feature: Favorites

## Purpose

Favorites lets users mark movies, series, channels, and playable items they care about and retrieve them from a dedicated library surface, search, details, For You, and player controls.

## Status

- Target state: favorite state is provider-scoped, persisted locally, visible across relevant surfaces, and synchronized with search/recommendation indexes.
- Current implementation: `FavoritesScreen` is a placeholder. `PlayerView` has a favorite control that toggles local `@State` only and does not persist. No favorite table is present in the current schema.

## User Experience

- Users can add or remove a favorite from detail screens and the player.
- Favorites tab lists all favorited content with useful grouping/filtering.
- Favorite state appears consistently on browse tiles, details, search results, player controls, and For You where applicable.
- Removing a favorite updates all visible surfaces without app restart.
- Empty Favorites shows a clear empty state.

## Data and State

- Target state should store provider ID/fingerprint, media identity, media type, created timestamp, and optional display snapshot fields.
- Favorite records should reference local media where possible and survive app relaunch.
- Search and recommendations should observe favorite changes or update their indexes.
- Current state is only transient player UI state.

## Key Files

- `iptv/UI/Screens/FavoritesScreen.swift`
- `iptv/Player/PlayerView.swift`
- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/UI/Screens/ForYouScreen.swift`
- `iptv/Model/Database/Schema.swift`

## Target Acceptance Criteria

- Favorite add/remove persists locally and is provider-scoped.
- Favorites tab renders persisted favorites from local state.
- Player and detail favorite buttons reflect the same persisted state.
- Favorite changes are immediately reflected in search/recommendation surfaces that are loaded.
- Deleting or changing provider state does not show stale favorites for another provider.
- Empty, loading, and unavailable states are explicit.

## Current Gaps / Planned Work

- No persisted favorite model/table exists in the current schema.
- `FavoritesScreen` is a placeholder.
- Player favorite toggle is local-only.
- Browse and detail favorite controls are not active.
- Search and For You do not consume favorite state.

## Notes for Agents

- Do not ship favorites as view-local state. The feature is only useful when persisted and shared.
- Update player, detail, search, and For You docs when favorite state becomes a real cross-surface dependency.
- Keep provider isolation explicit in the data model.
