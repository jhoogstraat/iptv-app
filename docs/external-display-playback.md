# Feature: External Display Playback

## Purpose

External Display Playback lets an iPhone or iPad remain a private browsing and control surface while video uses the full resolution of a connected television or monitor. The feature covers wired USB-C/Lightning docks and adapters using HDMI or DisplayPort, Apple AirPlay video and external-display routes without reducing the television to a mirror of the device UI.

The target experience is one playback session with one authoritative `Player`, one active video destination, and controls that remain useful on the device. Output discovery and destination lifecycle are separate from stream decoding so the existing VLC-first/AV-fallback player architecture remains intact.

## Status

- Target state: the app detects eligible displays and receivers, lets the user move playback between them without restarting the media, renders clean full-screen video on wired external displays, uses native AVFoundation external playback for AirPlay.
- Implementation status (reviewed 2026-07-16): the app now creates one `PlaybackDestinationCoordinator` beside `Player`, declares a noninteractive external-display scene, bridges that scene to the existing runtime, arbitrates one renderer host, and provides the wired display surface, device controller mode, and persistent now-playing bar. The runtime bridge buffers external-scene connections during cold launch and replays them after bootstrap. Controller dismissal preserves off-device playback but closes local playback so no session becomes unreachable. VLC owns one persistent decoder-bound drawable surface for the playback session and reparents that surface between renderer hosts; owner tokens prevent a late source-view teardown from unmounting the replacement host. AVPlayer allows and observes native external playback; route changes can perform a position-preserving VLC-to-AV handoff when the current URL is AV-compatible. Destination loss pauses and requires explicit local continuation.
- Product priority: wired HDMI/DisplayPort is the first milestone because it is the strongest differentiator and can reuse both current local playback backends. AirPlay hardening follows on the AV backend.

## User Experience

### Destination selection

- A single `Source` control appears with the other bottom-left player menus. It reports the active app-owned destination (`This Device`, `External Display`), contains audio-track selection, and groups the system `AVRoutePickerView` beneath it instead of presenting separate, competing controls.
- Connecting a wired display does not add an app-level banner or top bar. The display becomes available in `Source`, and the initial default remains the device to avoid exposing private content unexpectedly.
- Starting an item while a previously selected destination is available sends it directly to that destination. Changing destination during playback preserves position, play/pause intent, selected item, and supported preferences.

### Device-as-controller mode

- After video moves off-device, the iPhone or iPad shows a controller surface rather than a duplicate video renderer: artwork, title/episode/channel information, destination name, connection/buffering state, play/pause, seek where supported, channel or episode navigation when available, audio/subtitle controls, and `Play on This Device`.
- The user can dismiss the expanded controller and continue browsing the local library. A persistent compact now-playing bar above the tab bar/sidebar restores the controller and exposes play/pause plus the active destination.
- `PlayerPresentationLifecycleModifier` preserves playback when an off-device controller disappears because the compact now-playing bar can restore it. Dismissing a local full-screen player closes that session because there is no local now-playing affordance outside the presentation.
- Device volume controls local wired/AirPlay output where the platform supports it.

### Television/monitor surface

- A wired external display gets a dedicated full-screen, noninteractive scene. It shows only video on black, preserving the selected aspect mode without device safe-area padding, toolbars, sheets, or touch controls.
- Before playback, the display shows a restrained `Ready to Play` screen with the app name and connected-device name. During loading or recoverable failure it shows a TV-readable status. Transport overlays appear only briefly after a command and then fade.
- AirPlay video uses the receiver’s native media presentation through AVFoundation rather than mirroring the complete SwiftUI player.

### Disconnects and privacy

- Unplugging a wired display, ending AirPlay, or losing a Cast session updates the controller immediately. By default playback pauses and offers `Continue on This Device`; it must not unexpectedly start audible video on a phone the user may have put down.
- A short transient disconnect may reconnect to Cast and reconcile receiver position before offering local continuation. Commands made while reconnecting have clear pending/failed states and are not silently dropped.
- Provider credentials and raw stream URLs are never displayed in route UI, logs, analytics, artwork metadata, or error copy.

## Data and State

### Shared destination model

- Add a main-actor observable `PlaybackDestinationCoordinator`, created once beside `Player` in `ApplicationRuntime` and injected at the app root.
- It owns:
  - `availableDestinations`
  - `selectedDestination`
  - connection state (`disconnected`, `connecting`, `connected`, `reconnecting`, `failed`)
  - external scene identity and display metadata
  - destination capabilities such as remote seek, tracks, subtitles, rate, volume, and live-stream support
  - the user’s pending handoff and per-connection wired-display preference
- `Player` remains authoritative for the current media item, logical play/pause state, timeline, watch activity, and player controls. The coordinator requests a handoff through explicit `Player` methods; views never manipulate backend or scene objects directly.
- Do not model a television as an `OutputRoute` only. `OutputRoute` currently describes audio/system routing, while a playback destination also owns renderer placement, remote session lifecycle, and capabilities.

### Wired HDMI/DisplayPort and external AirPlay displays

- Declare a `UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene configuration on iOS/iPadOS and attach an `ExternalDisplaySceneDelegate`. UIKit supplies this scene when a supported physical cable or AirPlay display connects; the scene spans the external screen.
- Host an `ExternalDisplayView` in that scene using `UIHostingController`. It reads the same `Player` and destination coordinator through a small runtime bridge owned by the existing application bootstrap; it must not create a second `Player`, provider session, or database.
- Make renderer ownership explicit. `PlayerRendererContainer` gains a host identity, and only the selected host (`device` or a concrete external scene) may mount the VLC drawable or AV presentation surface. The VLC backend retains one persistent drawable and moves it between host wrapper views during handoff so the active VLC video output is not rebound or recreated.
- Keep decoding local for wired output. Both VLC and AV backends remain eligible, so extensionless or VLC-only Xtream streams can still use the television. The display scene changes where frames render, not which catalog item or provider session is active.
- Treat scene connection/disconnection as presentation events. They must not reset the `Player`, write false completion progress, or trigger the existing VLC-to-AV runtime fallback.

### Native AirPlay video

- Configure the AV backend’s `AVPlayer` for external playback and observe whether external playback is active. Continue to use the system `AVRoutePickerView` with video devices prioritized.
- If AirPlay video is chosen while VLC is active, perform one controlled VLC-to-AV destination handoff only when the resolved URL is AV-compatible. Carry current time for VOD/catch-up, autoplay intent, and supported selections. If AV cannot play the stream, leave local playback intact and explain that the current stream is not AirPlay-compatible.
- Do not create both an external display renderer and AVPlayer external playback for the same route. The coordinator resolves one active mode from scene presence and AVPlayer external-playback state and guarantees a single video destination.

### Persistence and telemetry

- Persist only user preferences such as `prefer wired display when connected`; do not persist ephemeral route identifiers as durable availability.
- Continue writing `WatchActivity` through `Player` for exactly one logical playback session. Remote progress events must use the same ordered/throttled write path so destination handoffs cannot regress progress.
- Log destination kind, transition, duration, result, and sanitized failure category. Never log resolved URLs, usernames, passwords, query tokens, or Cast media custom data containing credentials.

## Key Files

- Existing files to extend:
  - `iptv/IPTVApp.swift`
  - `iptv/State/Player.swift`
  - `iptv/Player/PlaybackBackend.swift`
  - `iptv/Player/PlaybackBackends.swift`
  - `iptv/Player/PlayerRendererContainer.swift`
  - `iptv/Player/PlayerView.swift`
  - `iptv/Player/AVKitContentView.swift`
  - `iptv/Player/VLCKitContentView.swift`
  - `iptv/UI/Views/ViewModifiers.swift`
  - `iptv/UI/ContentView.swift`
  - `iptv/Info.plist`
- Planned focused files:
  - `iptv/State/PlaybackDestinationCoordinator.swift`
  - `iptv/ExternalDisplay/ExternalDisplaySceneDelegate.swift`
  - `iptv/ExternalDisplay/ExternalDisplayView.swift`
  - `iptv/ExternalDisplay/ExternalPlaybackControllerView.swift`
  - `iptv/ExternalDisplay/ExternalNowPlayingBar.swift`
- Related specifications:
  - `docs/video-player.md`
  - `docs/advanced-player-ui-spec.md`
  - `docs/app-navigation.md`
  - `docs/app-architecture.md`

## Target Acceptance Criteria

- Connecting a supported HDMI or DisplayPort adapter creates a dedicated full-screen external scene instead of mirroring the device player UI.
- Wired external video fills the display bounds, preserves source aspect ratio according to player settings, and works with both VLC and AV local backends.
- Exactly one renderer host owns video at a time; switching or disconnecting never produces duplicate audio, a stale VLC drawable, or two competing video surfaces.
- The iPhone/iPad remains usable for browsing and controlling playback while the external screen continues playing.
- Dismissing the controller does not stop playback; explicitly closing the logical playback session does.
- AirPlay selection uses the native route picker, reflects the active route, and either hands compatible playback to AVPlayer without restarting from zero or leaves local playback intact with a useful incompatibility message.
- Movies, episodes, catch-up programs, and live streams declare destination capabilities honestly; unavailable seek, track, codec, or route behavior is disabled with explanatory copy.
- A destination loss pauses safely by default, preserves the last reliable position, and offers continuation on the device.
- Watch progress remains monotonic across local, wired and AirPlay with no duplicate logical playback sessions.
- No provider credential or raw resolved playback URL appears in UI, logs, analytics, or unsanitized errors.
- VoiceOver labels announce the destination, connection state, and result of handoffs; controls remain usable with Dynamic Type and Switch Control.
- Real-device tests cover at least one iPhone and one iPad, a USB-C HDMI/DisplayPort adapter or dock and an AirPlay receiver. Simulator-only validation is not accepted for shipping.

## Current Gaps / Planned Work

### Completed architecture and wired MVP

- `PlaybackDestinationCoordinator`, destination/capability models, renderer-host arbitration, and duplicate/disconnect tests are active.
- Logical off-device playback lifetime is separate from full-screen controller presentation lifetime; local dismissal closes playback to keep it reachable and user-controlled.
- External-scene notifications arriving before database/runtime bootstrap are buffered and replayed, with cold-launch and pre-install disconnect coverage.
- A compact now-playing controller remains in the main shell while playback is off-device.
- The wired noninteractive scene, shared runtime bridge, edge-to-edge TV surface, controller mode, safe pause-on-loss behavior, and sanitized external error copy are implemented.
- External windows use the screen’s preferred mode, disable UIKit overscan scaling, fill the scene bounds, and update their frame after geometry changes. `Fit` may still letterbox mismatched source/display aspect ratios; `Fill` occupies the display by cropping.
- VLC preserves its decoder-bound drawable across host replacement and reparents it to the selected host; AV renderer surfaces explicitly detach during replacement.

### Remaining wired validation

- Validate resolution, overscan/safe-area behavior, rotation, screen-mode changes, background/foreground transitions, sleep/wake, rapid cable reconnect, and both VLC/AV playback on physical hardware.

### Remaining AirPlay hardening

- Harden asynchronous AV readiness/rollback beyond the current compatibility-gated handoff and verify receiver route naming.
- Validate direct AirPlay video, AirPlay-created external display scenes, route changes during playback, receiver sleep, device lock, live streams, subtitles, and audio-track behavior.

### Milestone 4: polish and release gating

- Add Now Playing/remote-command integration so lock-screen and headset controls operate the one logical playback session where platform policy permits.
- Add optional automatic wired-display preference, destination diagnostics, analytics, and a first-use explanation.
- Run long-play soak tests, repeated 100-cycle handoff tests, network-loss tests, memory/thermal profiling, accessibility QA, and App Store privacy/configuration review.

## Notes for Agents

- Preserve `Player` as the single owner of logical playback and watch progress. Do not create a second player model per scene.
- Destination selection, renderer placement, and decoding backend selection are related but distinct state machines. Keep their transitions explicit and testable.
- A wired external scene is not an AirPlay audio route. Do not extend the existing `OutputRoute` model until these concepts are separated.
- Never create or bind a second VLC drawable during active playback. Move the backend-owned persistent surface from the previous host to the next host, and use owner-scoped teardown so stale view destruction cannot remove it.
- Do not stop a working local backend until a remote AirPlay handoff has succeeded. Rollback must preserve the current item and position.
- Keep platform SDK imports behind compile guards so macOS, tvOS, visionOS, tests, and previews continue to build.
- Update this feature spec, `docs/video-player.md`, and `docs/app-navigation.md` when implementation changes playback lifetime, root presentation, or destination ownership.
