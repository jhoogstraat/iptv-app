# Feature: Downloads and Offline

## Purpose

Downloads and Offline lets users queue supported VOD or series content for local storage and play completed downloads without relying on network streaming.

## Status

- Target state: downloads are queueable, resumable, persisted, storage-aware, provider/profile scoped, and integrated with playback fallback.
- Current implementation: `DownloadsScreen` currently shows a not-implemented state, with substantial commented-out row/control ideas. Older planning exists in `docs/downloads-offline-spec.md`.
- Current player integration: offline playback source selection is not implemented.

## User Experience

- Downloads tab shows in-progress, paused, failed, and completed downloads.
- Users can pause, resume, retry, cancel, remove, and play completed downloads.
- Completed downloads should display an offline-ready affordance.
- Storage and network failures should show actionable errors.
- Unsupported content, such as live streams, should be clearly unavailable for offline download.

## Data and State

- Target state includes download item/group identity, provider/profile identity, media identity, source URL, local URL, status, progress, timestamps, error state, and manifest/checksum metadata.
- Download queue should survive app relaunch.
- Player should choose local completed assets when offline or when explicitly playing offline.
- Current schema has no download tables or manifest integration.

## Key Files

- `iptv/UI/Screens/DownloadsScreen.swift`
- `iptv/UI/Views/DownloadStatusBadge.swift`
- `iptv/State/Player.swift`
- `iptv/Model/Database/Schema.swift`
- `docs/downloads-offline-spec.md`

## Target Acceptance Criteria

- Supported content can be enqueued for download.
- Download status and progress persist across relaunch.
- Pause, resume, retry, cancel, remove, and remove-all actions work predictably.
- Completed downloads play from local files when selected.
- Corrupt, missing, or unavailable local files produce recovery actions.
- Live streams are not offered as downloadable content unless live recording is explicitly implemented.
- Download state is provider/profile scoped and does not leak across providers.

## Current Gaps / Planned Work

- `DownloadsScreen` is not implemented.
- `DownloadStatusBadge` contains commented planned behavior but no active integration.
- No download manager, queue, manifest, or persisted model exists in the current schema.
- Playback URL/source selection does not support local downloaded assets.
- Storage management UI is absent.

## Notes for Agents

- Downloads is one feature even though it spans UI, queueing, disk storage, playback, and media details.
- Do not implement UI controls without a real persisted download state machine behind them.
- Reconcile this doc with `docs/downloads-offline-spec.md` before implementation and update stale terminology.
