# Live TV, EPG, and Catch-up Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: Deferred after basic channel-only Live TV.
- Implementation status (reviewed 2026-07-06): Basic live category/channel sync, local channel browsing, and live channel playback are implemented in `docs/live-tv.md`. EPG program cache, guide timeline, catch-up resolver, zapping state, DVR, and program schema remain planned-only.

## Objective
Deliver the complete IPTV live experience with channel navigation, guide context, and catch-up where provider support exists.

## In Scope
- Existing prerequisite: channel-only Live TV listing and playback is handled by `docs/live-tv.md`.
- EPG timeline view:
  - current program
  - upcoming programs
  - program details.
- Channel zapping:
  - quick previous/next channel actions.
- Catch-up playback for eligible programs.
- Continue watching support for live programs with catch-up support.

## Out of Scope
- DVR recording.
- Multi-view mosaic.
- Advanced parental lock and content filtering.

## Data Requirements
- Channel entity:
  - id, name, logo, category, stream URL, language, provider metadata.
- Program entity:
  - id, channelID, title, startTime, endTime, description, catchupAvailable.
- Guide coverage metadata:
  - last refresh time, duration covered, missing windows.

## Service Requirements
- Add provider service methods for:
  - EPG by channel and time window
  - catch-up URL resolution for program/time range.
- Keep live category/channel sync in the channel-only Live TV feature; this spec starts at guide/catch-up data.
- Cache EPG windows with TTL and background refresh.

## UX Requirements
- Keep the existing channel-only Live tab as the fallback surface.
- Add a real guide timeline only after provider-scoped program windows exist; do not show fake guide rows.
- Program details sheet should include:
  - watch live
  - watch from start (if catch-up available).
- Player should show current channel/program metadata and allow quick channel up/down only after EPG/zapping state exists.

## Player Integration
- Live player mode should include:
  - no fixed duration for pure live streams.
  - progress timeline only for catch-up sessions.
- Seek availability depends on catch-up mode and provider support.

## Failure Handling
- Missing EPG data:
  - still allow live playback through the existing channel list.
  - show honest missing-guide copy only in real guide surfaces; do not add empty guide shells to channel-only Live.
- Catch-up resolution failure:
  - keep live playback available and show retry action.

## Testing

## Unit
- EPG window merge and cache TTL logic.
- Catch-up availability computation.
- Channel zapping state transitions.

## Integration
- Channel selection starts live playback through the channel-only Live feature.
- Program selection starts catch-up playback when available.
- Fallback from missing EPG to channel-only live view.

## UI
- Timeline navigation and current-time marker behavior.
- Program details actions and availability badges.
- Channel up/down controls in player.

## Acceptance Criteria

- User can browse channels and start live playback before guide data exists.
- User can view guide data once EPG sync/cache exists.
- Catch-up works for eligible programs and degrades gracefully when unavailable.
- Live tab supports day-to-day IPTV usage without fake EPG rows.

