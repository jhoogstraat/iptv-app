# Feature: App Navigation

## Purpose

App navigation provides the stable shell that organizes discovery, watch, library, and settings surfaces after onboarding. It should keep tab identity stable across platforms while allowing each feature to own its internal navigation stack.

## Status

- Target state: one root gate decides onboarding versus main shell; one canonical tab model defines app surfaces; feature screens own their internal stacks and detail routing.
- Implementation status (reviewed 2026-07-15): `Tabs` provides stable non-localized customization IDs, `ContentView` renders the `sidebarAdaptable` shell, and every data-backed top-level surface is mounted through `SessionGuard`, including Search. Movies, Series, and Live use native category `NavigationLink`s before media/channel destinations, so system back controls and interactive back gestures preserve the category landing context. Movies and Series place `SessionGuard` outside the `NavigationStack`, so category, movie, series, and episode destinations inherit the same `Session`. Detail routes use `MediaDetailDestination`; player presentation is wired through root full-screen presentation, visionOS window presentation, and macOS `PlayerWindow`.
- Current gaps: detail navigation still uses feature-local stacks rather than one central route enum or shared `NavigationPath`.

## User Experience

- After onboarding, users land in the main tab shell.
- Top-level surfaces are `For You`, `Search`, `Movies`, `Series`, `Live`, `Favorites`, `Downloads`, and `Settings`.
- Movies and Series are grouped under Watch.
- Favorites and Downloads are grouped under Library.
- Settings is grouped separately.
- On non-macOS/non-tvOS platforms, sidebar/tab customization persists through app storage while pinned tabs remain non-customizable.

## Data and State

- `ContentView` owns `selectedTab: Tabs`.
- `Tabs` owns stable integer IDs, localized names, SF Symbols, and customization IDs.
- `SessionGuard` injects `Session` into guarded feature content when an active session exists.
- Movies and Series each use their own `NavigationStack` around `BrowseScreen`; `SessionGuard` wraps that owning stack so every pushed detail destination inherits `Session`.
- Live owns its feature-local `NavigationStack`. Its category rows push `LiveCategoryScreen` before channel interaction.
- Settings uses a `NavigationStack` with `SettingsDestination` values for subpages.
- Player presentation is modeled by `Player.presentation` and is wired at the app root through `IPTVApp`, `withVideoPlayer()`, and macOS `PlayerWindow`.

## Key Files

- `iptv/Model/Tabs.swift`
- `iptv/UI/AppRootView.swift`
- `iptv/UI/ContentView.swift`
- `iptv/UI/SessionGuard.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/SettingsScreen.swift`
- `iptv/UI/Views/ViewModifiers.swift`
- `iptv/PlayerWindow.swift`
- `iptv/IPTVApp.swift`

## Target Acceptance Criteria

- `AppRootView` is the only app-level choice between onboarding and the main shell.
- `Tabs` is the canonical source for tab identity, labels, icons, and customization IDs.
- Movies and Series require a session and receive it through `SessionGuard`.
- Search tab uses SwiftUI's search tab role.
- Feature screens do not duplicate tab identity constants.
- Detail routes preserve user context inside the owning feature stack.
- Movies, Series, and Live category routes return to their landing list through native back navigation and do not model navigation as filter state.
- Player presentation can be reached from detail/play actions without remounting the whole app shell.

## Current Gaps / Planned Work

- `DownloadsScreen` is mounted from the Downloads tab and presents the profile/provider-scoped download queue.
- There is no central route enum or shared `NavigationPath` for cross-tab media details.
- Feature-local navigation is intentional today; a central path should be added only when real cross-tab deep-link requirements exist.

## Notes for Agents

- Add new top-level surfaces through `Tabs` and `ContentView`; do not hardcode tab labels in multiple places.
- Keep feature-specific navigation inside the feature unless multiple tabs must deep-link to the same destination.
- Before changing player presentation, inspect `ViewModifiers.swift`, `PlayerWindow.swift`, and `IPTVApp.swift` together.
