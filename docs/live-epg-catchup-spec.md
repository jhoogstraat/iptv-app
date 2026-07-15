# Feature: Live TV, EPG, and Catch-up

## Purpose

Provide channel playback with current/upcoming guide context, adjacent-channel zapping, and catch-up where the provider marks a program eligible.

## Status

Implemented for Xtream short-EPG responses, on-demand guide presentation, eligible catch-up URL resolution, and previous/next channel controls. DVR recording remains out of scope.

## User Experience

- Live remains playable when guide data is missing or fails.
- Selecting a channel shows current and upcoming programs when available.
- Eligible past programs offer catch-up playback.
- Player controls can zap to the previous or next channel in the current channel list.

## Data and State

- Live channel rows persist EPG channel ID, catch-up capability, catch-up duration, and current guide metadata.
- `LiveGuideService` fetches and maps short EPG data on demand and resolves Xtream catch-up URLs.
- Catch-up uses bounded program start/duration; ordinary live playback remains non-seekable.

## Key Files

- `iptv/UI/Screens/LiveScreen.swift`
- `iptv/Model/LiveGuideService.swift`
- `iptv/State/Player.swift`
- `iptv/Player/MediaPlaybackSourceResolver.swift`
- `iptv/Model/Database/Schema.swift`

## Target Acceptance Criteria

- Missing guide data never blocks live playback.
- Guide responses are mapped into truthful program rows.
- Catch-up is offered only for eligible programs and resolution failures are visible.
- Previous/next controls load adjacent channels without stale playback state.

## Current Gaps / Planned Work

- EPG windows are fetched on demand rather than persisted as a long-lived program cache.
- DVR recording, multi-view, and parental locking are not implemented.
- Provider-specific catch-up URL variants may require additional capability mapping.

## Notes for Agents

- Keep channel-only playback as the fallback when guide calls fail.
- Do not expose catch-up without provider capability and a valid program time range.
