# Core Application Finish Spec (Movies E2E + Pluggable Player Backends)

## Summary
Finish the core user path for macOS and iOS: Movies list -> Movie detail -> Playback.  
Use a protocol-based backend architecture where VLC is primary and AVKit is fallback/secondary.  
Use Xtream metadata only (`get_vod_info`) for this pass.  
Remove hardcoded provider credentials and introduce user configuration.

## Current State Analysis (Updated February 22, 2026)
1. Implemented: provider configuration with Keychain + app storage split, dynamic `Catalog` service binding, Settings flow, and Movies empty-state CTA for missing config.
2. Implemented: protocol-based player backends (`VLC` primary, `AV` secondary), backend factory selection, async event stream, runtime fallback guardrails, and timeline/seek support.
3. Implemented: stable player shell with swappable renderer container, Movie detail bound to Xtream metadata, scoped non-MVP placeholders, and logging for provider/network/playback paths.
4. Implemented: unit tests for backend selection/fallback, player delegation/progress, provider persistence split, mapper edge cases; UI tests for missing-config CTA and Settings entry.
5. Remaining risk: full build/test verification is blocked in this environment by offline SwiftPM dependency fetch and CoreSimulator service mismatch.

## Architecture Decisions (Locked)
1. `PlaybackBackend` is UI-agnostic and must not return SwiftUI views (`AnyView` is disallowed).
2. The player UI is a single stable shell (`PlayerView`) shared across all backends.
3. Only the renderer subview is swapped (`VLC` view vs `AV` view); controls and screen state remain mounted.
4. Runtime fallback from VLC to AV must support asynchronous playback failure after initial render.
5. Secrets storage uses Keychain for credentials; non-sensitive config uses app storage.
6. Backend state transport uses `AsyncStream<PlaybackEvent>`; UI binds to `Player` observable state.

## Public Interfaces / Types
1. Add `enum PlaybackBackendID { case vlc, av }`.
2. Add `enum PlaybackState { case idle, loading, ready, playing, paused, buffering, failed(String) }`.
3. Add `enum PlaybackEvent` (minimum):
   `.ready(duration: Double?)`, `.playing`, `.paused`, `.buffering(Bool)`, `.progress(currentTime: Double, duration: Double?)`, `.ended`, `.failed(Error)`.
4. Add `protocol PlaybackBackend`:
   `id`, `isAvailable`, `canPlay(url:contentType:containerExtension:)`, `load(url:autoplay:)`, `play()`, `pause()`, `togglePlayback()`, `stop()`, `seek(to:)`, `events() -> AsyncStream<PlaybackEvent>`.
5. Add `PlaybackBackendFactory`:
   priority order `[VLCPlaybackBackend, AVPlaybackBackend]`, choose first available/capable backend.
6. Add `ProviderConfig`:
   `baseURL` in `UserDefaults/AppStorage`; `username` and `password` in Keychain.
7. Add `PlayerRendererContainer`:
   single renderer host subview that switches renderer implementation based on active backend and a refresh token.

## Player Orchestration and Fallback Rules
1. `Player` owns current backend instance, `activeBackendID`, `rendererRevision`, and `playbackState`.
2. `PlayerView` remains constant; it mounts one `PlayerRendererContainer` plus shared controls/labels/error UI.
3. `PlayerRendererContainer` rebuilds only the renderer when backend changes or `rendererRevision` increments.
4. Playback state machine:
   `idle -> loading -> ready|buffering|playing|paused -> failed|ended`.
5. Fallback policy:
   if VLC fails during `load` or later async playback startup, attempt one automatic fallback to AV for the same item.
6. Guardrail:
   `didFallbackForCurrentItem` prevents retry loops; second failure becomes terminal `.failed(...)` and user-visible error.
7. `canPlay` policy:
   missing/unknown container is treated as playable by VLC; AV check stays stricter.
8. Progress policy:
   backend emits `.progress` while media is loaded; `Player` normalizes values into observable timeline fields used by the transport slider.

## UX / Product Behavior
1. Fresh install:
   app opens normal tab shell; Movies shows empty state with “Configure Provider” CTA.
2. Settings flow:
   add/edit provider config; validate before saving; no catalog fetch before valid config exists.
3. Non-MVP tabs:
   keep visible but explicitly labeled “Not in current release scope”.
4. Movie detail:
   remove placeholder sections/text; bind visible content to Xtream `vod_info` fields and available artwork.
5. Player controls:
   slider, current time, and duration are driven by `Player` timeline state sourced from backend `.progress` events.

## Open Tasks (Execution Status)
1. [x] Add provider config models/services and Keychain integration; remove literals from `IPTVApp.swift`.
2. [x] Implement `PlaybackBackend` protocol, concrete VLC and AV backends, and backend factory.
3. [x] Refactor `Player` into state-machine orchestrator with async event consumption and fallback.
4. [x] Introduce `PlayerRendererContainer` and update player surfaces (`VLCKitContentView`, AV wrapper) so only renderer swaps while `PlayerView` stays stable.
5. [x] Finalize Movies and Detail states (loading, empty, error, retry) and wire Play action through new `Player`.
6. [x] Replace generic placeholder strings in non-MVP tabs with explicit scoped messaging.
7. [x] Add logging for backend selection/fallback and provider/network failures.

## Verification Notes (Updated February 22, 2026)
1. Attempted local macOS build via `xcodebuild -project iptv.xcodeproj -scheme iptv -destination 'platform=macOS' -derivedDataPath /tmp/iptv-derived build`.
2. Build could not complete in sandbox due to network restriction fetching `swift-collections` (`Could not resolve host: github.com`).
3. Environment also reports CoreSimulator framework mismatch (`1051.9.4` vs required `1051.17.7`), limiting simulator-based verification.

## Tests and Acceptance Criteria
1. Unit: backend factory chooses VLC first, AV fallback when unavailable/unsupported.
2. Unit: async VLC failure triggers single fallback to AV; second failure ends in terminal error.
3. Unit: `Player` commands delegate correctly to active backend and update `playbackState`.
4. Unit: provider config persistence split (base URL in defaults, credentials in Keychain).
5. Unit: Xtream mapper parsing covers missing container/rating metadata edge cases.
6. Unit: progress events update `Player` timeline state and `seek(to:)` delegates to active backend.
7. UI smoke: Movies -> Detail -> Play succeeds with valid provider config and transport slider updates over time.
8. UI negative: no config shows setup CTA; invalid credentials/network shows recoverable error.
9. UI fallback: when VLC fails at runtime, renderer swaps to AV while controls remain visible and interactive.

## Out of Scope for MVP
1. Watch progress/resume synchronization.
2. Subtitle and audio track selection UI/management.
3. Picture-in-Picture support.
4. TMDB enrichment and cross-provider metadata merging.

## Assumptions and Defaults
1. Cross-platform parity is required for macOS and iOS in this pass.
2. Xtream is the only data source for detail metadata in MVP.
3. VLC is the default backend whenever available and not explicitly disqualified.
4. Automated test bar is core-path coverage plus manual playback verification on both platforms.
