# Feature: Library Sync and Local Data

## Purpose

Library sync turns remote Xtream catalog data into local app state. The local library is the source of truth for browsing, search, details, recommendations, favorites, progress, and offline metadata.

## Status

- Target state: initial sync seeds the local library, background sync keeps it fresh, and screens read local data without direct provider fetches.
- Implementation status (reviewed 2026-07-14): `SyncManager.sync()` single-flights initial sync, rejects non-2xx provider or proxy response headers before waiting for a body, bounds providers that never answer and later category responses that stall, requires at least one received category across movie, series, and live, and atomically replaces the catalog only after all required families succeed. Category hydration is single-flight and reconciles incoming movie/series/live rows by deleting stale rows and updating timestamps. Provider changes invalidate active sync/detail/hydration ownership so stale work cannot commit into a replacement catalog.
- Current schema: a fresh development database is created complete in one initial `Create tables` registration with provider, category, media, category-prefix-visibility, series-season, watch-activity, and favorites tables plus current indexes and metadata/write-order columns. Provider passwords live only in Keychain behind a database credential reference; `providers` has no plaintext password column. Before release, there is intentionally no compatibility migration chain for older development databases.

## User Experience

- During onboarding, the user sees initial sync phases for Movies, Series, and Live.
- After sync, Movies, Series, and Live can show category lists immediately.
- Opening a category for the first time may trigger stream/channel hydration for that category.
- Once hydrated, category content should render from local `Media` rows.
- Sync errors should be recoverable without losing provider configuration unnecessarily.

## Data and State

- `providers`: provider identity, endpoint, Keychain credential reference, source kind, explicit insecure-HTTP approval, active flag, and initialized flag.
- `categories`: source category ID, media type, display title, and hydration timestamp.
- `media`: source stream ID, media type, title, category ID, rich detail metadata, episode/series linkage, container extension where available, and update timestamp. Live rows persist available channel metadata without inventing EPG data.
- `SyncManager.InitialSyncPhase`: idle, checking provider, syncing movies, syncing series, syncing live, validating received data, replacing catalog, succeeded, failed.
- `SyncManager.SyncStatus`: idle, active, success, failure.
- `Category.updatedAt == nil` means the category has not been lazily hydrated yet.
- `watch_activity`: provider-scoped movie/episode progress with ordered write-session/generation stamps so late asynchronous writes cannot regress newer progress. Live playback does not persist watch progress.
- Schema setup is a clean pre-release cutover: development databases created by an older migration chain must be deleted and recreated rather than migrated or shimmed.

## Key Files

- `iptv/State/SyncManager.swift`
- `iptv/State/Session.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/LiveScreen.swift`
- `iptv/UI/Onboarding/OnboardingFlowView.swift`

## Target Acceptance Criteria

- Initial sync preserves the last good catalog until movie, series, and live category fetches all succeed, then replaces catalog rows atomically.
- Initial sync terminates with actionable failures immediately on non-2xx provider/proxy response headers, or after bounded waits when the provider does not answer, a later response stalls, or all three category payloads are empty.
- Movie, series, and live category sync state is visible to onboarding.
- Lazy category hydration fetches streams/channels only when needed, reconciles stale children, and stamps `Category.updatedAt` on success.
- Hydrated category media is stored locally and reused by browse/search/detail/live surfaces.
- Provider changes invalidate old work before clearing/replacing the singleton catalog, preventing stale commits or cross-provider leakage.
- Sync failures preserve the last good catalog and expose meaningful retry copy.

## Current Gaps / Planned Work

- Initial sync does not currently prefetch all media rows.
- Background incremental sync is not implemented.
- Provider-isolated user state exists for category prefix visibility, watch progress, and favorites; downloads and recommendations are not yet present in the current schema.
- Media records do not include playable URL fields, language, audio tracks, subtitle tracks, or full cast/crew normalization.
- Provider isolation is mixed: user-state tables are provider-scoped, while `categories` and `media` have no provider column; provider sync/delete paths clear the singleton local library, and active-provider filters prevent watch progress from leaking across providers.
- A release migration policy is not defined yet; add compatibility migrations before shipping only when preserving an installed production schema becomes a real deployment requirement.

## Notes for Agents

- Treat sync as infrastructure for multiple features. Update this doc when changing how library rows are created, invalidated, or refreshed.
- Do not add screen-level remote fetches for routine rendering. Route new data needs through sync/local persistence unless the fetch is explicitly playback URL resolution or detail enrichment.
- If adding advanced filters, update schema/index docs and this sync doc together.
