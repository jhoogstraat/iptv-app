# Feature: Settings and Provider Management

## Purpose

Settings gives users a place to inspect provider status, edit provider credentials, manage library organization preferences, configure playback defaults, and access support/about information.

## Status

- Target state: Settings is the durable management surface for provider configuration, library organization, playback defaults, and app information.
- Implementation status (reviewed 2026-07-10): `SettingsScreen` has Provider, Library, Playback, and About destinations. Provider removal is explicitly named and confirmed; resync preserves provider configuration, favorites, and watch history; unchanged and name-only saves preserve initialization/catalog state; connection changes require onboarding sync. Prefix visibility is database-backed per provider. Playback and About help/legal remain explicit placeholders.
- Current provider behavior: name-only changes update display state without destroying catalog rows. Endpoint, username, password, or insecure-transport changes rebuild an uninitialized session and route through onboarding. Explicit removal deletes provider credentials and provider-owned local state after confirmation.

## User Experience

- Settings overview lists Provider, Library, Playback, and About destinations.
- Provider page shows honest category/media counts and setup/sync status.
- Provider editor saves provider changes, resyncs catalog data, or removes the provider through separate consequence-specific actions.
- Library page exposes detected prefix visibility controls backed by provider-scoped database rows; language-source/grouping controls remain disabled.
- Playback page explains current player-default limitations; controls remain disabled until Settings owns their persisted contract.
- About page shows app version while support/legal destinations remain placeholders.

## Data and State

- `SettingsDestination` controls subpage routing.
- `ProviderFields` holds editable name, endpoint, username, password, and explicit insecure-HTTP approval.
- `@FetchOne(Provider.where(\.isActive))` supplies the active provider row; password material is resolved through `ProviderCredentialStoring`, not SQLite.
- Local category/media queries supply provider status counts with truthful labels.
- `ProviderManager` classifies unchanged, name-only, connection-changing, resync, and removal operations so destructive effects are explicit.
- `CategoryPrefixVisibility` and provider credentials persist through database rows and Keychain respectively. Player preferences currently use device `UserDefaults` from the player runtime rather than active Settings controls.

## Key Files

- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/UI/Views/ProviderEditorView.swift`
- `iptv/UI/Views/StatCard.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/IPTVApp.swift`

## Target Acceptance Criteria

- Settings reads and writes active provider state through `ProviderManager`.
- Unchanged and name-only provider saves preserve initialization, catalog, favorites, and watch history.
- Connection-changing saves reset initialization and require successful onboarding sync before browsing.
- Explicit resync preserves provider configuration and user state while replacing catalog rows.
- Provider removal requires confirmation and removes provider credentials plus provider-owned local state.
- macOS Settings scene uses the same `ProviderManager` instance as the main app.

## Current Gaps / Planned Work

- `Group categories by prefix` and `Language Source` remain disabled until their data contracts exist.
- Playback defaults remain disabled; wiring them requires one explicit device- or profile-scoped persistence contract.
- About help/licenses/terms remain placeholders.
- Provider passwords are stored in Keychain, with SQLite containing only credential references and migration/compensation behavior for failures.

## Notes for Agents

- Keep provider editing behavior consistent between onboarding and Settings by using `ProviderEditorSection` and `ProviderFields`.
- Do not enable a Settings control before adding the corresponding persisted state and feature behavior.
- If Settings starts running sync directly, update `onboarding-flow.md` and `library-sync-local-data.md`.
