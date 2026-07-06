# Feature: App Navigation

## Purpose

App navigation provides the stable shell that organizes discovery, watch, library, and settings surfaces after onboarding. It should keep tab identity stable across platforms while allowing each feature to own its internal navigation stack.

## Status

- Target state: one root gate decides onboarding versus main shell; one canonical tab model defines app surfaces; feature screens own their internal stacks and detail routing.
- Implementation status (reviewed 2026-07-06): Partial. `Tabs` is the canonical tab identity model, `ContentView` renders a `sidebarAdaptable` tab shell, Search uses SwiftUI's search role, Movies/Series are session-guarded `NavigationStack`s, browse/search rows route to `MediaDetailDestination`, series detail episode rows route to `EpisodeDetailTile`, and root player presentation is wired through `IPTVApp`, `.withVideoPlayer()`, and macOS `PlayerWindow`.
- Current gaps: For You, Live, and Favorites are inline placeholders; Downloads delegates to a placeholder `DownloadsScreen`; there is still no central route enum or shared `NavigationPath` for media details.

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
- Movies and Series each use their own `NavigationStack` around `BrowseScreen`.
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
- Player presentation can be reached from detail/play actions without remounting the whole app shell.

## Current Gaps / Planned Work

- `ContentView` currently inlines the For You placeholder instead of using `ForYouScreen`.
- Live and Favorites currently use inline placeholders instead of their screen structs.
- `DownloadsScreen` is mounted from the Downloads tab but still shows a not-implemented state.
- There is no central route enum or `NavigationPath` for media details.
- Several top-level surfaces are not complete navigable experiences yet: For You, Live, Favorites, and Downloads.

## Notes for Agents

- Add new top-level surfaces through `Tabs` and `ContentView`; do not hardcode tab labels in multiple places.
- Keep feature-specific navigation inside the feature unless multiple tabs must deep-link to the same destination.
- Before changing player presentation, inspect `ViewModifiers.swift`, `PlayerWindow.swift`, and `IPTVApp.swift` together.
