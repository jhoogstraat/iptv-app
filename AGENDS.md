# General Application Functionality

## Overview
`iptv` is a native SwiftUI IPTV client for Apple platforms. The app connects to a remote Xtream provider, replicates the remote library into local SwiftData storage, and renders the UI from that local database for fast browsing, search, and playback.

## Core Flow
1. The app starts by loading the active provider session from local state.
2. If a provider is configured, the app builds an `XtreamService` and starts the sync engine.
3. If no provider is available, the app presents Settings so the user can configure one.
4. The sync engine performs an initial full replication of the remote library, then keeps the local database up to date in the background.
5. Screens read from SwiftData rather than querying the remote API directly.

## Remote Library Sync
- The remote source is the Xtream API.
- The sync engine is responsible for pulling down the library of movies, series, and live TV channels.
- Initial sync seeds the local database for navigation, search, and detail views.
- Background sync should be incremental and low priority, with an emphasis on keeping local data fresh without blocking the UI.
- The local database is the source of truth for persisted library state, favorites, watch activity, and downloaded/offline metadata.

## Main User Surfaces
- `For You` provides the landing experience and discovery entry point.
- `Movies` and `Series` expose the local library by category.
- `Live` represents the live channel surface.
- `Favorites` shows user-marked content.
- `Downloads` surfaces offline or pending download state.
- `Search` lets users find items from the persisted library.
- `Settings` is used to configure the Xtream provider and app preferences.

## Playback
- Playback is handled by the player subsystem, which presents a stable player UI while swapping the renderer/backend as needed.
- VLC is the preferred backend when available, with AVKit as a fallback path.
- Playback state, progress, and transport behavior are managed locally so the UI can stay responsive during backend changes.

## Data Model
- SwiftData stores the application’s persistent state.
- Provider configuration, categories, media items, watch progress, and related metadata live in the local database.
- App screens and supporting services should work from Swift value types or view state, not from raw `@Model` instances crossing layers.

## Product Intent
- The app should feel like a local media library once synced, even though the data originates from a remote IPTV provider.
- Users should be able to open the app, browse content immediately after sync, search locally, and resume playback from stored watch state.
- Remote fetches are for synchronization and refresh, not for routine screen rendering.
