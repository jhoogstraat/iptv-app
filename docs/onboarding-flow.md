# Feature: Onboarding Flow

## Purpose

Onboarding gets the user from a fresh install or uninitialized provider to a locally synced catalog. It is the only first-run path for provider selection, Xtream credentials, initial sync progress, and retry after setup failure.

## Status

- Target state: first launch presents onboarding, captures a provider, runs initial sync, marks the provider initialized only after successful sync, and then routes into the main app shell.
- Current implementation: `AppRootView` shows `OnboardingFlowView` whenever `ProviderManager.requiresOnboarding` is true. `OnboardingFlowView` supports source selection, credentials, syncing, and failed states. Xtream API is supported; M3U8 playlist is shown disabled as coming soon.
- Current sync scope: initial sync clears local `Media`/`Category` rows and syncs movie and series categories. Live is not part of the active initial sync.

## User Experience

- Fresh install opens to a dark onboarding surface with a source selection step.
- The user selects `Xtream API`, enters source name, endpoint, username, and password, and starts sync.
- The syncing step shows progress rows for Movies and Series and a phase message such as preparing storage or syncing categories.
- If sync succeeds, the provider is marked initialized and root routing switches to `ContentView`.
- If sync fails, onboarding shows a retry form with the sync error or fallback guidance.
- If an active provider exists but is not initialized, onboarding should prefill provider fields and resume the sync path automatically.

## Data and State

- `ProviderManager.requiresOnboarding` is true when there is no session or the active provider is not initialized.
- `ProviderManager.initialize(_:)` inserts a new active provider.
- `ProviderManager.update(provider:)` upserts credentials, marks the provider uninitialized, and rebuilds the active session.
- `ProviderManager.runInitialSyncForActiveProvider()` delegates to `Session.runInitialSync()` and sets `Provider.isInitialized = true` only on success.
- `SyncManager.InitialSyncPhase` drives onboarding phase copy.
- `SyncManager.SyncStatus` drives per-media-type progress icons.
- `ProviderFields` validates name, username, password, and normalized Xtream endpoint.

## Key Files

- `iptv/IPTVApp.swift`
- `iptv/UI/AppRootView.swift`
- `iptv/UI/Onboarding/OnboardingFlowView.swift`
- `iptv/UI/Views/ProviderEditorView.swift`
- `iptv/State/ProviderManager.swift`
- `iptv/State/Session.swift`
- `iptv/State/SyncManager.swift`
- `iptv/Model/Database/Schema.swift`
- `iptvTests/OnboardingTests.swift`

## Target Acceptance Criteria

- No provider: app shows onboarding, not the tab shell.
- Active initialized provider: app shows the tab shell, not onboarding.
- Active uninitialized provider: app resumes onboarding sync with prefilled provider fields.
- Incomplete or invalid provider fields do not create or update a provider.
- Successful initial sync marks the provider initialized exactly once and exits onboarding.
- Failed sync keeps the user in onboarding with an actionable retry path.
- Provider credentials are never hardcoded.

## Current Gaps / Planned Work

- `IPTVApp` still crashes on `loadActive()` failure because it uses `try!`; onboarding docs should not claim graceful database recovery yet.
- M3U8 playlist source is only a disabled planned option.
- Live TV is not included in the initial sync flow.
- Initial sync currently persists categories, while streams/media are hydrated lazily per selected category.
- Settings provider edits reset initialization, then root routing returns to onboarding for sync; Settings does not run sync inline today.

## Notes for Agents

- Treat onboarding as a single feature even though it spans app launch, provider persistence, sync, and root routing.
- Any provider setup change must be checked against `ProviderManager.requiresOnboarding` and `Provider.isInitialized` semantics.
- Keep retry behavior explicit. Do not silently route to the tab shell after a failed initial sync.
