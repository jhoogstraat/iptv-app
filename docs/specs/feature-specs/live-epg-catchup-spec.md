# Live TV, EPG, and Catch-up Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: Deferred (after downloads/offline in current roadmap)

## Objective
Deliver the complete IPTV live experience with channel navigation, guide context, and catch-up where provider support exists.

## In Scope
- Live TV channel listing and grouping.
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
  - live categories/channels
  - EPG by channel and time window
  - catch-up URL resolution for program/time range.
- Cache EPG windows with TTL and background refresh.

## UX Requirements
- Replace Live tab placeholder with:
  - channel rail/list
  - guide timeline.
- Program details sheet should include:
  - watch live
  - watch from start (if catch-up available).
- Player should show current channel/program metadata and allow quick channel up/down.

## Player Integration
- Live player mode should include:
  - no fixed duration for pure live streams.
  - progress timeline only for catch-up sessions.
- Seek availability depends on catch-up mode and provider support.

## Failure Handling
- Missing EPG data:
  - still allow live playback.
  - show "No guide data" placeholder in timeline region.
- Catch-up resolution failure:
  - keep live playback available and show retry action.

## Testing

## Unit
- EPG window merge and cache TTL logic.
- Catch-up availability computation.
- Channel zapping state transitions.

## Integration
- Channel selection starts live playback.
- Program selection starts catch-up playback when available.
- Fallback from missing EPG to channel-only live view.

## UI
- Timeline navigation and current-time marker behavior.
- Program details actions and availability badges.
- Channel up/down controls in player.

## Acceptance Criteria
- User can browse channels, view guide data, and start live playback.
- Catch-up works for eligible programs and degrades gracefully when unavailable.
- Live tab is no longer placeholder and supports day-to-day IPTV usage.

