# Feature: Live TV

## Purpose

Live TV gives users access to synced live channels, channel grouping, and eventually EPG/catch-up behavior while preserving the app's local-library feel.

## Status

- Target state: Live is a first-class watch surface backed by local live category/channel data, with channel playback through the shared player and future EPG/catch-up support.
- Implementation status (reviewed 2026-07-05): Planned-only. `LiveScreen` contains unused state and renders `Text("Not yet implemented")`; `ContentView` bypasses it with an inline “Live TV Is Out of Scope” placeholder. `SyncManager.liveSync` exists but live sync is commented out, `MediaType` has no live case, and no live/EPG schema or channel playback routing exists.
- Existing planning: `docs/live-epg-catchup-spec.md` contains older roadmap details.

## User Experience

- Live tab should show channel categories/groups after sync.
- Users can filter/search channels locally.
- Tapping a channel should start playback through the shared player.
- Missing provider or missing live content should show useful empty states.
- Future EPG should show current/next programming and catch-up where supported.

## Data and State

- Target local state: live categories, channels, stream identifiers, logos, group/prefix metadata, EPG programs, catch-up availability, and provider-scoped refresh timestamps.
- Current `MediaType` includes `episode` but no dedicated live media case in the visible enum.
- Current schema does not include EPG or live-channel-specific tables.
- Player should consume resolved live stream URLs without special UI forks unless live-specific metadata is needed.

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

- `LiveScreen` renders `Text("Not yet implemented")`, and the active tab currently bypasses it with an inline out-of-scope placeholder.
- Live sync is not active.
- No live-specific local schema exists.
- No channel playback URL resolution or live media routing is connected.
- EPG and catch-up are planned but absent.

## Notes for Agents

- Do not bypass the local-library architecture for routine live browsing.
- If introducing live media types, update schema, mapper, sync, tabs/navigation, search/filter, and player docs together.
- Keep EPG/catch-up separate from basic channel playback so the initial Live surface can ship incrementally without fake EPG data.
