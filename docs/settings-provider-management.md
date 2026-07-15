# Feature: Settings and Provider Management

## Purpose

Settings gives users a place to inspect provider status, edit provider credentials, manage library organization preferences, configure playback defaults, and access support/about information.

## Status

- Target state: Settings is the durable management surface for provider configuration, library organization, playback defaults, and app information.
- Implementation status (reviewed 2026-07-15): `SettingsScreen` has Provider, Profiles, Library, Playback, and About destinations. Playback defaults persist in device `UserDefaults` and are consumed by `Player`; Help, license, and terms/privacy documents open real local content. Prefix visibility is database-backed per provider.
- Current provider behavior: name-only changes update display state without destroying catalog rows. Endpoint, username, or password changes rebuild an uninitialized session and route through onboarding. Explicit removal deletes provider credentials and provider-owned local state after confirmation. HTTPS is preferred and used for scheme-less input; HTTP Xtream providers require an explicit per-provider warning acknowledgement.

## User Experience

- Settings overview lists Provider, Library, Playback, and About destinations.
- Provider page shows honest category/media counts and setup/sync status.
- Provider editor saves provider changes, resyncs catalog data, or removes the provider through separate consequence-specific actions.
- Library page exposes detected prefix visibility controls backed by provider-scoped database rows.
- Playback page persists preferred backend, subtitle default, and preferred audio/subtitle languages.
- About page shows app version and opens local help, license, and terms/privacy documents.

## Data and State

- `SettingsDestination` controls subpage routing.
- `ProviderFields` holds editable name, HTTP(S) endpoint, username, password, and persisted insecure-HTTP approval. The approval toggle is always available; enabling it reveals the transport warning, while HTTP validation still requires the opt-in.
- `@FetchOne(Provider.where(\.isActive))` supplies the active provider row; password material is resolved through `ProviderCredentialStoring`, not SQLite.
- Local category/media queries supply provider status counts with truthful labels.
- `ProviderManager` classifies unchanged, name-only, connection-changing, resync, and removal operations so destructive effects are explicit.
- `CategoryPrefixVisibility` and provider credentials persist through database rows and Keychain respectively. Playback Settings and `Player` share the same device-scoped `UserDefaults` keys.

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

- Normalized provider language metadata and a configurable language-source contract remain planned.
- Playback preferences are device-scoped rather than profile-scoped.
- Provider passwords are stored in Keychain, with SQLite containing only credential references and migration/compensation behavior for failures.

## Notes for Agents

- Keep provider editing behavior consistent between onboarding and Settings by using `ProviderEditorSection` and `ProviderFields`.
- Do not enable a Settings control before adding the corresponding persisted state and feature behavior.
- If Settings starts running sync directly, update `onboarding-flow.md` and `library-sync-local-data.md`.
