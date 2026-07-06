# Feature: Library Sync and Local Data

## Purpose

Library sync turns remote Xtream catalog data into local app state. The local library is the source of truth for browsing, search, details, recommendations, favorites, progress, and offline metadata.

## Status

- Target state: initial sync seeds the local library, background sync keeps it fresh, and screens read local data without direct provider fetches.
- Implementation status (reviewed 2026-07-06): Partial. `SyncManager.sync(provider:)` clears all local `Media` and `Category`, fetches VOD and series categories, and stores category rows. `BrowseScreen` lazily hydrates unhydrated movie/series categories through `Session.update(_:in:)`, which upserts `Media` rows and stamps `Category.updatedAt`. Provider-scoped `WatchActivity` now persists movie/episode progress separately from catalog rows.
- Current schema: provider, category, media, series season, category prefix visibility, and watch-activity tables exist; favorites, downloads/offline, live channels, provider-isolated catalog rows, and recommendation persistence are not yet visible in the current schema.

## User Experience

- During onboarding, the user sees initial sync phases for Movies and Series.
- After sync, Movies and Series can show category lists immediately.
- Opening a category for the first time may trigger stream hydration for that category.
- Once hydrated, category content should render from local `Media` rows.
- Sync errors should be recoverable without losing provider configuration unnecessarily.

## Data and State

- `providers`: provider identity, endpoint, credentials, source kind, active flag, initialized flag.
- `categories`: source category ID, media type, display title, update timestamp.
- `media`: source stream ID, media type, title, category ID, TMDB ID, cover URL, rating, update timestamp.
- `SyncManager.InitialSyncPhase`: idle, clearing library, syncing movies, syncing series, succeeded, failed.
- `SyncManager.SyncStatus`: idle, active, success, failure.
- `Category.updatedAt == nil` means the category has not been lazily hydrated yet.
- `watch_activity`: provider-scoped movie/episode progress keyed by provider ID, media type, and source ID, with title/artwork/category snapshots, time/duration, completed flag, last watched, and update timestamps.

## Key Files

- `iptv/State/SyncManager.swift`
- `iptv/State/Session.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Onboarding/OnboardingFlowView.swift`

## Target Acceptance Criteria

- Initial sync clears stale library rows before loading the new provider's categories.
- Movie and series category sync state is visible to onboarding.
- Lazy category hydration fetches streams only when needed and stamps `Category.updatedAt` on success.
- Hydrated category media is stored locally and reused by browse/search/detail surfaces.
- Provider changes do not leak categories or media from the previous provider.
- Sync failures preserve enough state to retry and show meaningful error copy.

## Current Gaps / Planned Work

- Initial sync does not currently prefetch all media rows.
- Live categories/channels are represented in intent but not active sync behavior.
- Background incremental sync is not implemented.
- Provider-isolated user state exists for category prefix visibility and watch progress; favorites, downloads, and recommendations are not yet present in the current schema.
- Media records do not include playable URL fields, language, audio tracks, subtitle tracks, or full cast/crew normalization.
- Provider isolation is mixed: user-state tables are provider-scoped, while `categories` and `media` have no provider column; provider sync/delete paths clear the singleton local library, and active-provider filters prevent watch progress from leaking across providers.

## Notes for Agents

- Treat sync as infrastructure for multiple features. Update this doc when changing how library rows are created, invalidated, or refreshed.
- Do not add screen-level remote fetches for routine rendering. Route new data needs through sync/local persistence unless the fetch is explicitly playback URL resolution or detail enrichment.
- If adding advanced filters, update schema/index docs and this sync doc together.
