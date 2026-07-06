# Basic Multi-Profile Spec

## Status
- Version: v1
- Date: 2026-02-24
- Priority: P2 after provider-scoped user state
- Implementation status (reviewed 2026-07-06): Deliberately deferred. Provider-scoped favorites and watch activity now exist, but there is still no `UserProfile`, `ProfileStore`, profile picker, profile management UI, migration, or profile-scoped playback preferences/search/download metadata. Do not add dormant profile services until a migration can create one active local profile named `Primary` and real consumers can read profile IDs.

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
- First rollout step:
  - create one active local profile named `Primary`.
  - migrate existing provider-scoped watch activity and favorites into `Primary` without changing visible user data.
  - only after that migration, widen persisted user-state keys from provider-scoped to `profileID + providerFingerprint + contentType + videoID`.

## Interfaces
- `ProfileStore` service:
  - `listProfiles()`
  - `createProfile(name:)`
  - `setActiveProfile(id:)`
  - `renameProfile(id:name:)`
  - `deleteProfile(id:)`
  - `activeProfile()`.

## Integration points
- `Player` should load and persist preferences for the active profile only after profile migration exists.
- `WatchActivityStore` should widen existing provider-scoped rows to active-profile scope during migration.
- `FavoriteStore` should widen existing provider-scoped rows to active-profile scope during migration.
- Search recents and filters should be scoped by active profile once recents persistence exists.
- Downloads metadata must not be introduced until the profile migration and download queue state machine exist.

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

