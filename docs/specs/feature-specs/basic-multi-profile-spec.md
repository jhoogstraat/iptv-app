# Basic Multi-Profile Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: P1 (ships with Library and Search)

## Objective
Add basic household profiles with isolated user state so each user has independent favorites, watch history, and playback preferences.

## In Scope
- Create profile.
- Switch active profile.
- Rename profile.
- Delete profile (with confirmation).
- Profile-scoped isolation for:
  - watch activity
  - favorites
  - playback preferences
  - search recents and filters
  - downloads metadata.

## Out of Scope
- Profile PIN lock.
- Parental ratings restrictions.
- Cloud sync across devices.

## UX Requirements
- Profile picker appears on app startup if more than one profile exists.
- Current profile is always visible in Settings and Library.
- Profile switch updates all visible data without app restart.

## Domain and Storage

## New model
- `UserProfile`
  - `id`, `name`, `avatar`, `createdAt`, `isActive`.

## Required keying changes
- Extend state keys from:
  - `providerFingerprint + contentType + videoID`
- to:
  - `profileID + providerFingerprint + contentType + videoID`.

## Migration
- On first run after profile feature rollout:
  - create default profile `Primary`.
  - re-map existing watch activity and favorites into `Primary`.

## Interfaces
- `ProfileStore` service:
  - `listProfiles()`
  - `createProfile(name:)`
  - `setActiveProfile(id:)`
  - `renameProfile(id:name:)`
  - `deleteProfile(id:)`
  - `activeProfile()`.

## Integration points
- `Player` should load and persist preferences for active profile only.
- `WatchActivityStore` should write/read scoped by active profile.
- `FavoritesStore` should write/read scoped by active profile.
- Search recents should be scoped by active profile.

## Failure Handling
- If profile data fails to load, app falls back to `Primary` profile and logs a recoverable error.
- Deleting active profile should atomically switch to another profile before finishing deletion.

## Testing

## Unit
- Profile CRUD.
- Isolation between two profiles on same provider.
- Migration from legacy single-profile data.
- Active profile switch propagation.

## Integration
- Continue watching changes immediately after profile switch.
- Favorites and search recents are isolated by profile.
- Player preferences apply per profile.

## UI
- Profile picker flows.
- Delete confirmation and fallback profile activation.
- Settings profile management actions.

## Acceptance Criteria
- Two profiles can coexist with no data leakage between them.
- Existing single-profile users retain prior data under the migrated `Primary` profile.
- Active profile switch updates UI state consistently across tabs.

