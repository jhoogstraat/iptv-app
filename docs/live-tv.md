# Feature: Live TV

## Purpose

Live TV gives users access to synced live channels, channel grouping, and eventually EPG/catch-up behavior while preserving the app's local-library feel.

## Status

- Target state: Live is a first-class watch surface backed by local live category/channel data, with channel playback through the shared player and future EPG/catch-up support.
- Implementation status (reviewed 2026-07-10): Basic channel-only Live is implemented. Initial sync includes live categories; `LiveScreen` reads local rows, lazily reconciles selected-category channels, applies shared normalized search/filter/sort and hidden-prefix visibility, and launches the shared player with an Xtream live URL. Empty/loading/failure states reflect local coverage honestly. EPG, catch-up, zapping, DVR, guide caching, downloads, profiles, and global Live search remain deferred.
- Existing planning: `docs/live-epg-catchup-spec.md` contains the deferred guide/catch-up roadmap.

## User Experience

- Live tab should show channel categories/groups after sync.
- Users can filter/search channels locally.
- Tapping a channel should start playback through the shared player.
- Missing provider or missing live content should show useful empty states.
- Future EPG should show current/next programming and catch-up where supported.

## Data and State

- Target local state: live categories, channel rows in `media` with `MediaType.live`, stream identifiers, titles, logos, category/group metadata, available stream type/added-date metadata, and future provider-scoped EPG/catch-up refresh state.
- Current `MediaType` includes `.live`; live channels reuse the existing `Media` table and `Category` table rather than a separate live-channel table.
- Current schema does not include EPG program, catch-up window, guide cache, DVR, or zapping tables.
- Player resolves `.live` rows through `XtreamMediaPlaybackSourceResolver` to the provider `/live/{username}/{password}/{sourceID}` path. Live mode hides seeking/timeline controls and shows copy that EPG, catch-up, zapping, DVR, and guide rows are unavailable.

## Key Files

- `iptv/UI/Screens/LiveScreen.swift`
- `iptv/UI/ContentView.swift`
- `iptv/State/SyncManager.swift`
- `iptv/State/Player.swift`
- `iptv/Model/Database/Schema.swift`
- `docs/live-epg-catchup-spec.md`

## Target Acceptance Criteria

- Live categories and channels are synced into local state.
- Live tab renders local channels without direct routine remote fetches.
- Search/filter behavior is local and consistent with browse/search semantics.
- Channel playback uses the shared player backend/fallback system.
- EPG/catch-up data, when implemented, is provider-scoped and refreshable independently from movies/series.
- Unsupported live features are visibly unavailable rather than silently omitted.

## Current Gaps / Planned Work

- EPG/current-next program data is not implemented.
- Catch-up playback and catch-up URL resolution are not implemented.
- Channel zapping, DVR/recording, guide caching, downloads/offline, profiles, and global Live search are deferred.
- Live channel rows are hydrated lazily by selected category; initial sync intentionally does not prefetch every channel.

## Notes for Agents

- Do not bypass the local-library architecture for routine live browsing.
- If introducing live media types, update schema, mapper, sync, tabs/navigation, search/filter, and player docs together.
- Keep EPG/catch-up separate from basic channel playback so the initial Live surface can ship incrementally without fake EPG data.
