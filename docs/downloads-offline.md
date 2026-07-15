# Feature: Downloads and Offline

## Purpose

Downloads and Offline lets users queue supported VOD or series content for local storage and play completed downloads without relying on network streaming.

## Status

Implemented for direct movie and episode files. Downloads are persisted, profile/provider scoped, can be paused (cancelled), resumed (restarted), retried, removed, and selected automatically for local playback. Live streams and series collections are not downloadable.

## User Experience

- Downloads tab shows in-progress, paused, failed, and completed downloads.
- Users can pause, resume, retry, cancel, remove, and play completed downloads.
- Completed downloads should display an offline-ready affordance.
- Storage and network failures should show actionable errors.
- Unsupported content, such as live streams, should be clearly unavailable for offline download.

## Data and State

- Target state includes download item/group identity, provider/profile identity, media identity, source URL, local URL, status, progress, timestamps, error state, and manifest/checksum metadata.
- Download records survive relaunch. Active transfers use foreground `URLSession` tasks; interrupted transfers remain persisted and can be resumed by restarting the transfer.
- Player chooses an existing completed local asset before resolving a remote provider URL.
- `download_items` stores profile/provider/content identity, source and local paths, status, errors, and timestamps.

## Key Files

- `iptv/UI/Screens/DownloadsScreen.swift`
- `iptv/UI/Views/DownloadStatusBadge.swift`
- `iptv/Model/DownloadStore.swift`
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

- Transfer byte progress and partial-file resume data are not persisted; Resume currently restarts the file transfer.
- Background URLSession restoration, storage quotas, checksums, and free-space preflight remain follow-up hardening.
- Live streams remain non-downloadable unless a separate recording feature is designed.

## Notes for Agents

- Downloads is one feature even though it spans UI, queueing, disk storage, playback, and media details.
- Do not implement UI controls without a real persisted download state machine behind them.
- Reconcile this doc with `docs/downloads-offline-spec.md` before implementation and update stale terminology.
