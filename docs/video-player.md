# Feature: Video Player

## Purpose

The video player provides stable playback controls and renderer switching across Apple platforms, preferring VLC when available and falling back to AVKit/AVPlayer when needed.

## Status

- Target state: detail/play actions load a playable media URL, choose the best backend, show a stable player shell, expose transport and advanced controls, persist progress/preferences, and recover through one safe fallback path.
- Implementation status (reviewed 2026-07-05): Partial. `Player`, `PlaybackBackend`, VLC and AV backends, `PlayerRendererContainer`, `PlayerView`, root presentation, and one-time VLC-to-AV fallback exist. `Player.playbackURL(for:)` now resolves active-provider Xtream movie/episode URLs through `MediaPlaybackSourceResolver`, and movie detail play actions can start real playback.
- Current blocker: persisted watch progress, persisted favorites, offline playback, profile-scoped preferences, fully wired episode quick switching, and complete quality/chapter UI exposure remain incomplete.

## User Experience

- Playback opens in a stable player UI without replacing the whole shell when the backend changes.
- Users can play/pause, seek, scrub, view elapsed/duration/remaining time, and close playback.
- Player shows backend, quality, buffering, error, and control status where applicable.
- Advanced controls include audio tracks, subtitles, quality, chapters, output route, speed, aspect ratio, audio delay, volume, brightness where supported, and sleep timer.
- Unsupported controls remain visible or explained rather than failing silently.
- Runtime VLC failure should attempt AV fallback once for the same item.

## Data and State

- `Player` owns current item, playback state, progress, active backend, renderer revision, capabilities, selected tracks, quality, chapters, output routes, speed, aspect ratio, audio delay, volume, brightness, sleep timer, and transient control messages.
- `PlaybackBackendFactory` selects VLC before AV by default.
- `PlaybackEvent` transports ready/playing/paused/buffering/progress/advanced-state/ended/failed updates.
- `PlayerRendererContainer` switches renderer by `activeBackendID` and `rendererRevision`.
- `PlayerAdvancedModels` defines tracks, quality variants, chapters, output routes, capabilities, aspect ratios, and sleep timer options.

## Key Files

- `iptv/State/Player.swift`
- `iptv/Player/PlaybackBackend.swift`
- `iptv/Player/PlaybackBackends.swift`
- `iptv/Player/PlayerAdvancedModels.swift`
- `iptv/Player/PlayerRendererContainer.swift`
- `iptv/Player/PlayerView.swift`
- `iptv/Player/VLCKitContentView.swift`
- `iptv/Player/AVKitContentView.swift`
- `iptv/Player/VLCCompatibility.swift`
- `iptv/UI/Views/ViewModifiers.swift`
- `iptv/PlayerWindow.swift`

## Target Acceptance Criteria

- VLC is selected first when available and capable.
- AV fallback is selected when VLC is unavailable, unsupported, or fails once at runtime.
- Fallback does not loop indefinitely.
- Renderer swaps do not reset the shared controls shell.
- Progress events update timeline UI and persisted watch progress policy.
- Advanced controls reflect backend capabilities and recover gracefully from unsupported operations.
- Playback can be launched from movie detail after URL resolution; series collections are intentionally rejected until episode rows are available.

## Current Gaps / Planned Work

- Persisted watch progress is not implemented; `persistProgressIfNeeded()` and `markCurrentItemCompleted()` are currently no-op/commented.
- Favorite toggle in `PlayerView` is local UI state only, not persisted.
- Some advanced preferences are learned or in-memory rather than exposed through Settings persistence.
- Episode quick switching appears planned/commented and is not fully active.
- Offline playback integration is planned but not implemented.

## Notes for Agents

- Do not replace the stable `PlayerView` shell when adding backend features. Swap only renderer/backend-specific surfaces.
- Backend capability checks should drive UI enabled/disabled states.
- Any playback URL work must update media detail, sync/data, and player docs because it crosses feature boundaries.
