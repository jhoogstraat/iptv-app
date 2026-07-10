# Feature: For You

## Purpose

For You is the landing and discovery experience. It should make the app feel like a local media library by surfacing continue watching, personalized recommendations, trending content, and new additions from locally synced state.

## Status

- Target state: For You renders a deterministic local discovery page using provider-scoped catalog data, favorites, and watch activity.
- Implementation status (reviewed 2026-07-10): `ForYouScreen` is live in the Home tab and derives one deterministic snapshot from local catalog, provider-scoped favorites/watch activity, category relationships, and hidden-prefix visibility. Its adaptive hero exposes truthful movie play/resume or series-detail actions, cards keep stable visible/accessibility identity when artwork loads, and sparse states distinguish loading, failed hydration, hidden content, and genuinely empty local data.
- Current navigation: `Tabs.home` presents `ForYouScreen`, and rail items route through `MediaDetailDestination`.

## User Experience

- For You should be the first tab after onboarding.
- The page should show a hero item when available.
- Continue Watching should prioritize unfinished local watch activity.
- Recommendation rails should be locally computed and provider-scoped.
- Empty states should distinguish missing provider, no synced content, and no watch history.
- Tapping items should route to the correct detail screen or playback action.

## Data and State

- Current inputs: local Movies, Series, and Episode catalog rows; provider-scoped watch progress; provider-scoped favorites; ratings; update dates; categories/groups; and category-prefix visibility.
- Current outputs: hero item, Continue Watching rail, Favorites rail, Top Rated Movies/Series rails, Recently Updated rail, explicit sparse-data states, and routing metadata.
- `WatchActivity` persists provider-scoped movie/episode progress in SQLite with source ID, media type, title/artwork/category snapshots, current time, duration, completed flag, last watched, and updated timestamps.
- `Favorite` persists provider-scoped media keys and display snapshots; For You joins favorites and watch activity back to live local `Media` rows before routing.

## Key Files

- `iptv/UI/Screens/ForYouScreen.swift`
- `iptv/UI/ContentView.swift`
- `iptv/UI/Views/ForYou/ForYouHeroView.swift`
- `iptv/UI/Views/ForYou/ForYouRailView.swift`
- `iptv/UI/Views/ForYou/ContinueWatchingCardView.swift`
- `iptv/Model/Database/Schema.swift`
- `docs/for-you-legacy.md`

## Target Acceptance Criteria

- For You renders from local provider-scoped state.
- Continue Watching includes only unfinished items with meaningful progress.
- Recommendation sections are deterministic for the same local data.
- Items already watched or completed are handled deliberately by section rules.
- Content routing works for movie and series items.
- Missing or sparse data produces useful empty states instead of blank rails.
- Prefix visibility and filters that affect recommendations are respected consistently.

## Current Gaps / Planned Work

- Rails intentionally stay deterministic and local; remote recommendation calls, recommendation indexes, profiles, downloads, and Live TV are deferred.
- The Favorites rail only routes rows that can be joined to current local `Media`; unavailable favorite snapshots remain visible in the Favorites tab.
- Continue Watching currently routes to the same detail destination as catalog rows, where resume/play actions are available.
- Sparse libraries can produce only a subset of rails; empty states explain whether the blocker is missing local catalog data, hidden category prefixes, or lack of user state.

## Notes for Agents

- Keep recommendations local and provider-scoped.
- Preserve category-prefix visibility for any catalog-derived rail.
- If profiles or downloads are added later, migrate favorite/watch keys deliberately instead of widening this screen ad hoc.
