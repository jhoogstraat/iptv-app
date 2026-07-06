# Feature: Settings and Provider Management

## Purpose

Settings gives users a place to inspect provider status, edit provider credentials, manage library organization preferences, configure playback defaults, and access support/about information.

## Status

- Target state: Settings is the durable management surface for provider configuration, library organization, playback defaults, and app information.
- Implementation status (reviewed 2026-07-05): Partial. `SettingsScreen` has Provider, Library, Playback, and About destinations; provider save/delete flows are active; macOS uses the same `ProviderManager`; and Library prefix visibility is partly active through `CategoryPrefixVisibilitySelector` plus provider-keyed `UserDefaults`. Playback defaults and About help/legal remain placeholders.
- Current provider behavior: editing provider credentials marks the provider uninitialized and active; root routing then returns to onboarding to run initial sync.

## User Experience

- Settings overview lists Provider, Library, Playback, and About destinations.
- Provider page shows category stats and setup status.
- Provider editor lets users save or clear provider configuration using the shared `ProviderEditorSection`.
- Library page exposes detected prefix visibility controls when categories exist; language-source/grouping controls remain disabled.
- Playback page communicates planned player defaults.
- About page shows support/legal placeholders and app version.

## Data and State

- `SettingsDestination` controls subpage routing.
- `ProviderFields` holds editable name, endpoint, username, and password.
- `@FetchOne(Provider.where(\.isActive))` supplies the active provider row.
- `@Fetch(MediaCount(provider: nil))` supplies movie/series media counts, although the current stats UI labels them as categories.
- `ProviderManager` applies save/clear behavior and session state changes.
- Planned state includes database-backed prefix visibility preferences, library language source, preferred player, default subtitle behavior, and preferred audio language.

## Key Files

- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/UI/Views/ProviderEditorView.swift`
- `iptv/UI/Views/StatCard.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptv/IPTVApp.swift`

## Target Acceptance Criteria

- Settings reads and writes active provider state through `ProviderManager`.
- Saving valid provider edits resets initialization so sync is required before normal browsing.
- Clearing provider state removes active provider state and local library rows as intended.
- Library organization settings are disabled or hidden until they are backed by persisted provider-scoped preferences.
- Playback defaults are disabled or hidden until they are backed by player preference persistence.
- macOS Settings scene uses the same `ProviderManager` instance as the main app.

## Current Gaps / Planned Work

- `Excluded Prefixes` and `Choose Visible Prefixes` are active when an active provider and detected groups exist, but the prefix preferences are stored in provider-keyed `UserDefaults`, not database rows.
- `Group categories by prefix` and `Language Source` are disabled.
- `Preferred Player`, `Enable subtitles by default`, and `Preferred Audio Language` are disabled.
- About page help/licenses/terms are placeholders.
- Provider credentials are stored in the current providers table; product-level secret storage expectations should be revisited before claiming Keychain behavior.

## Notes for Agents

- Keep provider editing behavior consistent between onboarding and Settings by using `ProviderEditorSection` and `ProviderFields`.
- Do not enable a Settings control before adding the corresponding persisted state and feature behavior.
- If Settings starts running sync directly, update `onboarding-flow.md` and `library-sync-local-data.md`.
