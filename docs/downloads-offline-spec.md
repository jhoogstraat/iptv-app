# Downloads and Offline Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: P2 (after player + library/search + profiles)

## Objective
Enable offline access for supported content with reliable queueing, storage management, and playback fallback when network is unavailable.

## In Scope
- Download queue:
  - enqueue
  - pause
  - resume
  - cancel
  - retry.
- Download progress and status UI.
- Per-profile download library.
- Storage management:
  - used/free space display
  - delete single item
  - delete all downloads.
- Offline playback fallback for downloaded items.

## Out of Scope
- Live channel recording/timeshift.
- DRM-protected license workflows.
- Cross-device download sync.

## Supported Content Rules
- Supported:
  - VOD files with direct downloadable URLs.
  - Series episodes with direct downloadable URLs.
- Not supported in v1:
  - provider content requiring token refresh every segment.
  - live streams.

## Architecture

## New module
- `iptv/Model/Downloads/DownloadManager.swift` (actor/service).

## New models
- `DownloadItem`
  - `id`, `profileID`, `videoID`, `contentType`, `sourceURL`, `localURL`, `status`, `progress`, `createdAt`, `updatedAt`.
- `DownloadStatus`
  - `queued`, `downloading`, `paused`, `completed`, `failed`, `canceled`.

## Storage layout
- Application Support:
  - `Downloads/{profileID}/{contentType}/{videoID}/...`
- Local manifest:
  - records metadata, file paths, checksum, and playable state.

## Playback Integration
- At play start:
  - if offline and local completed asset exists, play local asset.
  - else fallback to network URL.
- Player UI should show source badge:
  - `Offline` or `Streaming`.

## Failure Handling
- Network interruption:
  - move to `failed` with retry action.
- Insufficient storage:
  - block enqueue with explicit error and settings shortcut.
- Corrupted file:
  - mark as invalid and offer cleanup + redownload.

## UX Requirements
- Downloads tab replaces current placeholder.
- Each item displays status icon, progress bar, and actionable controls.
- Completed downloads have clear "Play Offline" affordance.

## Testing

## Unit
- Download queue transitions and state machine correctness.
- Disk manifest read/write consistency.
- Profile isolation of downloaded items.
- Free-space checks and failure transitions.

## Integration
- Offline playback path selects local file.
- Network playback path selected when no local file exists.
- Deleting a download removes files and manifest entry.

## UI
- Queue actions and status rendering.
- Error states for storage/network problems.
- Offline badge visibility during playback.

## Acceptance Criteria
- User can download supported content, view progress, and play it offline.
- Download actions are resilient across app relaunch.
- Downloads remain isolated per profile.

