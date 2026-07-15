# Feature: SwiftUI UI Architecture

## Purpose

The application UI should prefer standard SwiftUI containers, controls, presentation APIs, and accessibility semantics. Custom views and styles should exist where they express IPTV-specific behavior or a repeated semantic surface, while generic styling should remain small, composable, and centralized only after repetition is established.

## Status

- The current UI uses native navigation, lists, menus, searchable content, unavailable states, and platform presentation APIs across the main application surfaces.
- A repository-wide review on 2026-07-15 covered concrete SwiftUI views, view modifiers, button styles, and platform representables.
- Shared detail presentation, artwork sizing, filtering, placeholder, and playback-presentation primitives already exist. Movie and series detail destinations now live in focused files, use native transparent navigation chrome, and retain their separate screen layouts while sharing only semantic presentation primitives.
- The initial architecture pass removes duplicate root refresh tasks, restores native button semantics for playable download rows, and removes an unused duplicate player command helper.

## User Experience

- Interactive rows expose native button, toggle, picker, slider, navigation, focus, keyboard, and accessibility behavior whenever the corresponding SwiftUI control fits the interaction.
- Loading, empty, error, and retry states are explicit and do not leave a screen in an indefinite progress state after failure.
- Repeated media surfaces remain visually consistent without forcing poster, backdrop, row-thumbnail, detail, and player imagery into one inflexible component.
- Platform-specific controls and focus behavior remain intact where Apple platforms require different presentation.

## Data and State

- Views should derive presentation from the smallest stable state needed to update the UI.
- Expensive database collections should not be equality-compared or repeatedly indexed from `body` when a lightweight query result or revision can drive the same update.
- Mirrored presentation state must synchronize dismissals back to its owning model.
- Asynchronous loading state should represent idle/loading/success/failure explicitly when failure changes what the user can do next.

## Key Files

- `iptv/UI/AppRootView.swift`
- `iptv/UI/ContentView.swift`
- `iptv/UI/Views/ViewModifiers.swift`
- `iptv/UI/Views/ArtworkSizing.swift`
- `iptv/UI/Views/DetailPresentation.swift`
- `iptv/UI/Views/LibraryCategoryList.swift`
- `iptv/UI/Screens/BrowseScreen.swift`
- `iptv/UI/Screens/LiveScreen.swift`
- `iptv/UI/Screens/DownloadsScreen.swift`
- `iptv/UI/Screens/MovieDetailScreen.swift`
- `iptv/UI/Screens/SeriesDetailScreen.swift`
- `iptv/UI/Screens/MediaDetailDestination.swift`
- `iptv/UI/Views/MediaDetailSupport.swift`
- `iptv/Player/PlayerView.swift`

## Target Acceptance Criteria

- Native SwiftUI controls provide semantics for user actions unless a documented product interaction requires a custom gesture or control.
- Shared styling primitives describe a semantic component or repeated behavior rather than acting as a global collection of unexplained constants.
- Loading and empty-state components have one implementation per semantic use and honor reduced-motion and accessibility settings.
- Screen state updates do not perform avoidable full-library equality comparisons or repeated projection work on the main actor.
- Custom player and media-detail UI retains required IPTV playback, focus, track, route, enrichment, and platform behavior.
- UI architecture changes build on macOS and preserve relevant unit or snapshot coverage.

## Current Gaps / Planned Work

- Consolidate Browse poster skeletons and the duplicate shimmer modifier into one reduced-motion-aware primitive.
- Reuse the configurable library filter bar for Live group filtering and remove the duplicate filter implementation.
- Replace the prefix-visibility checkmark button with a standard `Toggle` and restore standard `NavigationLink` disclosure behavior in category lists.
- Give For You catalog loading an explicit failure state with retry instead of leaving the progress view active after a fetch error.
- Replace the custom iOS playback timeline with `Slider` unless a documented visual requirement justifies maintaining custom drag and accessibility behavior.
- Extract a duplicated movie/series detail scaffold only if future layout and platform-focus coverage demonstrates that a shared lifecycle abstraction is safer than the current focused screens.
- Consider a narrow artwork loader abstraction, while preserving context-specific sizing, content mode, placeholders, and accessibility.
- Remove provably unused legacy views and commented implementations in a separate cleanup.

## Notes for Agents

- Prefer `Button`, `Toggle`, `Picker`, `Slider`, `NavigationLink`, `ContentUnavailableView`, and standard presentation modifiers before building equivalents from gestures and images.
- Do not centralize all spacing, colors, `AsyncImage` uses, or card layouts merely because their syntax looks similar; first verify shared semantics and lifecycle.
- Treat the custom player controls and dark detail actions as intentional domain UI unless acceptance criteria permit simplification.
- Keep refactors small enough to verify across macOS, iOS, and tvOS behavior, especially focus, dismissal, and media presentation.
