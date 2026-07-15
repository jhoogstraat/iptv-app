# Feature: Video Player

## Purpose

The video player provides stable playback controls and renderer switching across Apple platforms, preferring VLC when available and falling back to AVKit/AVPlayer when needed.

## Status

- Target state: detail/play actions load a playable media URL, choose the best backend, show a stable player shell, expose transport and advanced controls, persist progress/preferences, and recover through one safe fallback path.
- Implementation status (reviewed 2026-07-14): `Player`, VLC/AV backends, stable renderer container, root presentation, and one-time VLC-to-AV fallback are active. AV accepts extensionless HTTP(S) Xtream streams; runtime fallback carries position and play/pause intent; track preferences apply after metadata arrives; live playback rejects seek/rate mutations at the player boundary; ordered watch writes prevent stale progress regression. Loading another item immediately stops and detaches the prior backend, clears per-item track/quality/chapter state, and releases a newly selected backend on terminal failure, so a failed handoff cannot leave old media playing behind the error surface. Selecting a concrete episode row in series detail loads that episode directly into the shared full-window player, while standalone episode detail routes retain their full-window play action. macOS windows dismiss cleanly, visionOS uses its own player window, and tvOS back/focus behavior is explicit.
- Current gaps: profile-scoped preferences, episode quick switching, and DVR live controls remain deferred.

## User Experience

- Playback opens in a stable player UI without replacing the whole shell when the backend changes.
- Switching items stops the prior backend before provider/source resolution; failure cannot leave the previous stream audible or its advanced controls visible.
- Users can play/pause, seek, scrub, view elapsed/duration/remaining time, and close playback.
- Player shows backend, quality, buffering, error, and control status where applicable.
- Advanced controls include audio tracks, subtitles, quality, chapters, output route, speed, aspect ratio, audio delay, volume, brightness where supported, and sleep timer.
- Unsupported controls remain visible or explained rather than failing silently.
- Live channel playback hides fixed-duration timeline/seek controls and shows explicit copy that EPG, catch-up, zapping, DVR, and seeking are unavailable for basic live streams.
- Runtime VLC failure should attempt AV fallback once for the same item.

## Data and State

- `Player` owns current item, playback state, progress, active backend, renderer revision, capabilities, selected tracks, quality, chapters, output routes, speed, aspect ratio, audio delay, volume, brightness, sleep timer, and transient control messages.
- `PlaybackBackendFactory` selects VLC before AV by default.
- `PlaybackEvent` transports ready/playing/paused/buffering/progress/advanced-state/ended/failed updates.
- `PlayerRendererContainer` switches renderer by `activeBackendID` and `rendererRevision`.
- `PlayerAdvancedModels` defines tracks, quality variants, chapters, output routes, capabilities, aspect ratios, and sleep timer options.
- `WatchActivity` stores provider-scoped movie/episode progress in SQLite, keyed by active provider ID, media type, and remote source ID. Player progress and ended events write rows asynchronously and throttle routine progress updates.
- Live `.media` rows resolve to Xtream `/live/{username}/{password}/{sourceID}` URLs. Live playback intentionally skips watch-progress persistence until catch-up/program time windows exist.

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
- `iptv/Player/MediaPlaybackSourceResolver.swift`
- `iptv/UI/Views/ViewModifiers.swift`
- `iptv/PlayerWindow.swift`

## Target Acceptance Criteria

- VLC is selected first when available and capable.
- AV fallback is selected when VLC is unavailable, unsupported, or fails once at runtime.
- Fallback does not loop indefinitely.
- Renderer swaps do not reset the shared controls shell.
- Progress events update timeline UI and persisted watch progress policy.
- Advanced controls reflect backend capabilities and recover gracefully from unsupported operations.
- Playback can be launched from movie detail, standalone persisted episode detail, concrete episode rows in series detail, and Live channel rows after URL resolution; series collection rows are intentionally rejected as non-playable.

## Current Gaps / Planned Work

- Favorite toggle in `PlayerView` reads and writes the provider-scoped local `FavoriteStore` for the current media item.
- Some advanced preferences are learned or stored device-globally in `UserDefaults` rather than exposed through profile-scoped Settings persistence.
- Episode quick switching is not active; selecting a persisted episode row in series detail launches the shared full-window player directly without routing through an intermediate detail screen.
- Live playback supports on-demand EPG context, eligible catch-up programs, and adjacent-channel zapping; DVR remains unimplemented.
- Completed movie and episode downloads are selected before remote URL resolution.

## Notes for Agents

- Do not replace the stable `PlayerView` shell when adding backend features. Swap only renderer/backend-specific surfaces.
- Backend capability checks should drive UI enabled/disabled states.
- Any playback URL work must update media detail, sync/data, and player docs because it crosses feature boundaries.
