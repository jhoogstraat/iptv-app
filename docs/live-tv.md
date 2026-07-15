# Feature: Live TV

## Purpose

Live TV gives users access to synced live channels, channel grouping, and eventually EPG/catch-up behavior while preserving the app's local-library feel.

## Status

- Live is backed by local category/channel data, with playback through the shared player. Native category navigation pushes a category-owned channel screen. Provider hydration runs off the main actor and the destination observation is scoped to that category; channel search/sort results are stored and computed once per compact criteria/catalog revision in a debounced, cancellation-propagating background worker rather than synchronously during SwiftUI body evaluation.
- Channel rows persist EPG identity and provider catch-up capability. The guide button requests short EPG data on demand, presents loading/empty/error/success states, and exposes Play from Start only when both the channel and programme advertise archive support.
- Previous/next player controls zap within the filtered local channel list. DVR and persistent guide caching remain deferred.

## User Experience

- Live opens on a sectioned list whose section titles are category groups and whose rows are live categories, even when some categories already have locally hydrated channels.
- Selecting a category pushes its channels with native SwiftUI navigation; category selection is not a filter, is not counted as active, and the system back button/back swipe returns to the category list.
- The landing filter state contains category Group/search only. The pushed channel screen has separate channel search/sort state.
- An unhydrated category immediately presents shimmer channel rows while fetch, decoding, and the atomic database reconciliation continue without blocking interaction.
- Users can filter/search channels locally.
- Tapping a channel should start playback through the shared player.
- Missing provider or missing live content should show useful empty states.
- Future EPG should show current/next programming and catch-up where supported.

## Data and State

- Target local state: live categories, channel rows in `media` with `MediaType.live`, stream identifiers, titles, logos, category/group metadata, available stream type/added-date metadata, and future provider-scoped EPG/catch-up refresh state.
- Current `MediaType` includes `.live`; live channels reuse the existing `Media` table and `Category` table rather than a separate live-channel table.
- EPG programmes are requested on demand rather than persisted. Channel rows store `epgChannelID`, `supportsCatchup`, and `catchupDays`.
- Player resolves live rows through the provider live path. Catch-up uses the provider timeshift path and is treated as seekable archived playback; live mode hides timeline controls and exposes zapping.
- The displayed channel result is reused for empty-state checks, row rendering, playback, and previous/next zapping; the full channel catalog is not repeatedly filtered during a render.
- `LiveScreen` observes categories and compact grouped counts. Each `LiveCategoryScreen` observes only its navigated category's channel rows; there is no cross-category channel observation on the landing screen.

## Key Files

- `iptv/UI/Screens/LiveScreen.swift`
- `iptv/UI/Views/LibraryCategoryList.swift`
- `iptv/UI/ContentView.swift`
- `iptv/State/SyncManager.swift`
- `iptv/State/Player.swift`
- `iptv/Model/Database/Schema.swift`
- `docs/live-epg-catchup-spec.md`

## Target Acceptance Criteria

- Live categories and channels are synced into local state.
- Movies, Series, and Live use the same sectioned category-list presentation as their default view.
- Category navigation uses the native feature stack and supports platform back navigation without representing the category as a filter.
- Live tab renders local channels without direct routine remote fetches.
- Search/filter behavior is local and consistent with browse/search semantics.
- Channel playback uses the shared player backend/fallback system.
- EPG/catch-up data, when implemented, is provider-scoped and refreshable independently from movies/series.
- Unsupported live features are visibly unavailable rather than silently omitted.

## Current Gaps / Planned Work

- EPG data is not cached locally and depends on provider short-EPG compatibility.
- Background guide refresh, DVR/recording, and full grid guide navigation remain deferred.
- Live channel rows are hydrated lazily by selected category; initial sync intentionally does not prefetch every channel.

## Notes for Agents

- Do not bypass the local-library architecture for routine live browsing.
- If introducing live media types, update schema, mapper, sync, tabs/navigation, search/filter, and player docs together.
- Keep EPG/catch-up separate from basic channel playback so the initial Live surface can ship incrementally without fake EPG data.
