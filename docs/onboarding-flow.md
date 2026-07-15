# Feature: Onboarding Flow

## Purpose

Onboarding gets the user from a fresh install or uninitialized provider to a locally synced catalog. It is the only first-run path for provider selection, Xtream credentials, initial sync progress, and retry after setup failure.

## Status

- Target state: first launch presents onboarding, captures a provider, runs initial sync, marks the provider initialized only after successful sync, and then routes into the main app shell.
- Current implementation: `AppRootView` shows `OnboardingFlowView` whenever `ProviderManager.requiresOnboarding` is true. A native SwiftUI `NavigationStack` owns source selection and credentials, including the system back affordance. Start Sync and Retry Sync present a native sheet that changes in place from progress to a titled retry form when synchronization fails; failure never pushes another navigation destination. Field-level validation, compact-height scrolling, and cancellation-safe sync are implemented. Credential recovery preserves the stored provider name, URL, username, and transport approval even when Keychain reads fail, leaving only the password empty for re-entry. Initial sync immediately rejects non-success provider response headers such as proxy HTTP 502, and stops with actionable errors when the provider never answers, a catalog request stops delivering data, or every required catalog family is empty. Xtream API is supported; M3U8 remains a disabled planned source.
- Current sync scope: initial sync fetches movie, series, and live categories, then atomically replaces the local catalog only after all required category families succeed. Streams/media are hydrated lazily per category.
- Implementation status (reviewed 2026-07-10): Xtream onboarding and retryable launch recovery are implemented. Successful sync alone marks the provider initialized. M3U8 remains planned.

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
- `SyncManager.InitialSyncPhase` drives onboarding phase copy, including provider contact and received-data validation.
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
- Initial sync fails within a bounded interval when the provider site cannot be reached or a later catalog response stalls.
- A non-2xx response from the provider or network proxy fails onboarding as soon as its HTTP headers arrive; sync does not wait for the response body or fallback timeout.
- A reachable provider must return at least one movie, series, or live category before onboarding can complete.
- Provider credentials are never hardcoded.

## Current Gaps / Planned Work

- M3U8 playlist source remains a disabled planned option.
- Initial sync persists movie, series, and live categories; streams/media remain lazily hydrated per selected category.
- Settings connection edits reset initialization, then root routing returns to onboarding for sync. Name-only or unchanged saves preserve the current catalog and user state.

## Notes for Agents

- Treat onboarding as a single feature even though it spans app launch, provider persistence, sync, and root routing.
- Any provider setup change must be checked against `ProviderManager.requiresOnboarding` and `Provider.isInitialized` semantics.
- Keep retry behavior explicit. Do not silently route to the tab shell after a failed initial sync.
