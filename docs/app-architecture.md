# Feature: App Architecture

## Purpose

The app should behave like a local media library backed by a remote Xtream provider. Remote APIs are used for synchronization and playback URL resolution; routine browsing, search, details, user state, and recommendations should read from local persisted state.

## Status

- Target state: provider configuration creates an active session, sync replicates provider catalog data into local persistence, screens render from local models, and playback operates through a stable player state model with swappable renderers.
- Implementation status (reviewed 2026-07-10): `IPTVApp` bootstraps SQLiteData/GRDB and active-provider state through a retryable `RecoverableBootstrap`, then injects one `ProviderManager` and `Player` into the root shell, Settings scene, and macOS player window. `ProviderManager` builds `Session`/`SyncManager`; For You, Search, Movies, Series, Live, Favorites, and Details read local catalog/user-state rows.
- Current persistence uses SQLiteData/GRDB tables and a singleton active-provider catalog. Provider-scoped credentials, prefix visibility, favorites, and watch activity are isolated even though category/media rows still rely on clean catalog replacement during provider changes.

## User Experience

- Launch should be immediate and deterministic.
- If no initialized provider exists, users enter onboarding.
- If an initialized provider exists, users enter the tab shell and can browse already-synced local categories.
- Remote latency should not block tab rendering except for explicit sync or lazy category hydration.
- Failure states should explain whether the app needs provider setup, sync retry, or a feature is not implemented yet.

## Data and State

- `Provider` stores provider name, endpoint, username, password, source kind, active flag, and initialization flag.
- `Category` stores provider category identity, media type, title, and lazy hydration timestamp.
- `Media` stores source ID, type, title, category relation, TMDB ID, cover URL, rating, and update timestamp.
- `ProviderManager` owns active provider/session state.
- `Session` wraps provider ID, sync state, and category update operations.
- `SyncManager` performs initial category sync and lazy per-category stream hydration.
- `Player` owns playback state, backend selection, advanced control state, and progress.

## Key Files

- `iptv/IPTVApp.swift`
- `iptv/UI/AppRootView.swift`
- `iptv/UI/ContentView.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/State/Session.swift`
- `iptv/State/SyncManager.swift`
- `iptv/State/Player.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/Model/Mapper.swift`
- `iptv/UI/SessionGuard.swift`

## Target Acceptance Criteria

- App launch loads the active provider once and routes through a single root gate.
- Screens never query Xtream directly for routine rendering; they read local persisted state or view state.
- Provider changes reset or isolate local library state so content never leaks across providers.
- Initial sync establishes enough local state for navigation to render without direct remote reads.
- Feature-specific state remains owned by the relevant subsystem and does not pass raw persistence models across unrelated layers when avoidable.
- Player UI remains stable while playback backends or renderers change.

## Current Gaps / Planned Work

- Launch database/provider failures render a retryable bootstrap failure surface instead of terminating the process.
- Initial sync atomically replaces category families after every required remote fetch succeeds; streams remain lazily hydrated when categories are opened.
- Live categories participate in initial sync, and live channel rows are persisted by lazy hydration.
- Watch progress, favorites, prefix visibility, live channels, seasons, episodes, and rich detail metadata are persisted. Downloads, profiles, recommendations, EPG/catch-up, and DVR remain deferred.
- For You, Search, Movies, Series, Live, Favorites, Settings, and media details are active surfaces. Downloads remains an explicit unsupported surface.

## Notes for Agents

- Keep docs and implementation aligned by updating this architecture doc when persistence ownership, root routing, sync boundaries, or environment injection change.
- Prefer local database reads for screen data. If a feature needs remote calls, describe whether the call is sync, detail enrichment, or playback resolution.
- Do not create a second app-wide architecture convention beside `ProviderManager` + `Session` + local persistence without deliberately migrating the existing one.
