# Feature: Basic Multi-Profile

## Purpose

Let household members keep independent favorites and watch progress while sharing the local provider catalog.

## Status

Implemented for local profile CRUD, active-profile switching, favorites, watch activity, browse badges, search indexes, details, and For You. The pre-release initial schema creates a `Primary` profile and keys persisted user state by profile and provider.

## User Experience

Settings contains a Profiles destination where users can create, select, rename, and delete profiles. Switching profiles refreshes profile-sensitive screens through a persisted revision signal. At least one profile must remain.

## Data and State

`user_profiles` stores profile identity. `favorites` and `watch_activity` use `profileID + providerID + mediaType + sourceID` uniqueness. The active profile ID is device-local in `UserDefaults`; missing state falls back to profile ID 1 (`Primary`).

## Key Files

- `iptv/Model/Database/Schema.swift`: initial schema, `UserProfile`, stores, and scoped state.
- `iptv/UI/Screens/SettingsScreen.swift`: profile management.
- `iptv/State/Session.swift`: active profile projection.
- Browse, Search, Favorites, For You, and detail screens: profile-filtered presentation.

## Target Acceptance Criteria

- Profiles can be created, selected, renamed, and deleted without deleting the final profile.
- Favorites and watch progress never leak between profiles on the same provider.
- Switching profile refreshes visible profile-sensitive content without restarting the app.
- A new database always contains the `Primary` profile.

## Current Gaps / Planned Work

- Startup profile picker, avatars, PINs, and parental restrictions are not part of the basic implementation.
- Playback defaults, downloads, and search-recents become profile-scoped when those persisted features are implemented.
- Add broader UI automation after stable accessibility flows exist.

## Notes for Agents

The product is not live, so profile columns belong in the single `Create tables` migration. Add compatibility migrations only after the first production schema ships. Any new user-owned persisted state must include `profileID` from the start.
