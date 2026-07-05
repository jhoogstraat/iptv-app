# Advanced Player UI Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: P0 (integral for product success)

## Objective
Ship a modern, reliable player experience across tvOS, iOS/iPadOS, and macOS with platform-specific UIs and shared playback behavior.

## In Scope
- Platform-specific player UIs:
  - tvOS: remote and focus-first overlay.
  - iOS/iPadOS: touch-first overlay with sheets.
  - macOS: keyboard/mouse-first overlay and menu commands.
- Core and advanced controls:
  - Play/pause, seek, scrubber, elapsed/total/remaining time.
  - Audio track selection.
  - Subtitle selection (in-stream tracks only, include Off).
  - Quality selection (Auto + manual variants when available).
  - Playback speed.
  - Aspect ratio modes (`Fit`, `Fill`, `16:9`, `4:3`, `Original`).
  - Audio delay adjustment (milliseconds, with reset to 0).
  - Chapter marker navigation when metadata exists.
  - Output device picker.
  - Sleep timer (`Off`, `15m`, `30m`, `60m`, `End of item`).
  - Add/remove favorites.
  - Episode quick switcher for series.
  - Volume control.
  - Brightness control on iOS/tvOS.

## Out of Scope
- Picture in Picture.
- External subtitle file loading (SRT/VTT).
- Cloud-sync of playback preferences.

## UX Requirements

## tvOS
- Overlay opens with Play/Pause button and remote menu action.
- Focus order is deterministic: transport -> media menus -> utility actions.
- Menus are side panels with one-depth navigation only.

## iOS/iPadOS
- Transport controls overlaid directly on player surface.
- Secondary controls open as bottom sheets.
- Brightness and volume are exposed as sliders in a dedicated quick settings sheet.

## macOS
- Overlay includes transport and status.
- Secondary controls are available from:
  - overlay buttons
  - menu commands
  - keyboard shortcuts.

## Shared Player Behavior
- Unsupported controls remain visible but disabled with an explanation.
- Manual quality stays active until changed back to Auto.
- Track and subtitle preferences should auto-apply by profile language preference when a matching track exists.
- Sleep timer pauses playback and exits full-window mode when fired.
- Episode quick switching should preserve player context and immediately start the selected episode.

## Data and Interface Additions

## New domain models
- `MediaTrack`
  - `id`, `kind`, `languageCode`, `label`, `isDefault`, `isForced`.
- `QualityVariant`
  - `id`, `label`, `bitrate`, `resolution`, `frameRate`, `isAuto`.
- `ChapterMarker`
  - `id`, `title`, `startSeconds`.
- `OutputRoute`
  - `id`, `name`, `isActive`.
- `PlaybackCapabilities`
  - boolean flags for track, subtitle, quality, chapters, output route, audio delay, brightness.

## Playback backend contract additions
- Read:
  - `capabilities()`
  - `audioTracks()`
  - `subtitleTracks()`
  - `qualityVariants()`
  - `chapterMarkers()`
  - `availableOutputRoutes()`
- Write:
  - `selectAudioTrack(id:)`
  - `selectSubtitleTrack(id:)`
  - `selectQualityVariant(id:)`
  - `setPlaybackSpeed(_:)`
  - `setAspectRatio(_:)`
  - `setAudioDelay(milliseconds:)`
  - `selectOutputRoute(id:)`
  - `setVolume(_:)`
  - `setBrightness(_:)`

## Persistence
- Store per-profile player preferences:
  - preferred audio language
  - preferred subtitle language and default enabled state
  - default speed
  - default aspect ratio
  - default audio delay.

## Failure Handling
- If metadata fetch fails, keep playback running and hide unavailable controls.
- If quality switch fails, revert to previous quality and show non-blocking error.
- If episode quick switch fails, continue current playback and show retry action.

## Testing

## Unit
- Capability mapping for VLC and AV backends.
- Track/quality/subtitle selection state transitions.
- Timer behavior and expiration handling.
- Preference application and fallback behavior.

## UI
- tvOS focus order and remote behavior.
- iOS sheet interactions and gesture conflicts.
- macOS menu and keyboard parity with overlay controls.
- Disabled states and error banners for unsupported controls.

## Acceptance Criteria
- User can complete all listed advanced control actions without leaving player screen.
- Platform-specific UI conventions are respected on tvOS, iOS/iPadOS, and macOS.
- Playback remains stable after repeated control changes (quality, track, subtitle, output route).

