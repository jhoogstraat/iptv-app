# Feature: For You

## Purpose

For You is the landing and discovery experience. It should make the app feel like a local media library by surfacing continue watching, personalized recommendations, trending content, and new additions from locally synced state.

## Status

- Target state: For You renders a personalized local discovery page using provider-scoped catalog data and watch activity.
- Implementation status (reviewed 2026-07-06): Partial shell only. `ForYouScreen` is a placeholder and `ContentView` inlines the same placeholder for the Home tab. Reusable For You components exist, `ContinueWatchingCardView` can display remaining time when handed watch activity, and provider-scoped `WatchActivity` rows are now queryable for the next Continue Watching rail; no recommendation query backs the surface yet.
- Current navigation: `Tabs.home` is the first tab, but `ContentView` currently does not present `ForYouScreen`.

## User Experience

- For You should be the first tab after onboarding.
- The page should show a hero item when available.
- Continue Watching should prioritize unfinished local watch activity.
- Recommendation rails should be locally computed and provider-scoped.
- Empty states should distinguish missing provider, no synced content, and no watch history.
- Tapping items should route to the correct detail screen or playback action.

## Data and State

- Target inputs: local Movies and Series catalog, provider-scoped watch progress, ratings, recency, categories/groups, favorites, and downloads where relevant.
- Target outputs: hero item, continue watching rail, recommendation rails, badges, and routing metadata.
- `WatchActivity` persists provider-scoped movie/episode progress in SQLite with source ID, media type, title/artwork/category snapshots, current time, duration, completed flag, last watched, and updated timestamps.
- Existing UI components include hero, rail, and continue-watching card views, but they are not connected to a recommendation or continue-watching data source.

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

- Active screen is a placeholder.
- `ContentView` does not currently use `ForYouScreen` for the home tab.
- Continue Watching still needs a rail/query layer that reads unfinished, meaningful `WatchActivity` rows for the active provider.
- Recommendation model/provider files referenced by older docs are not visible in the current file tree.
- Prefix visibility is available for browse/search and must be applied to recommendation queries once For You is backed by local data.

## Notes for Agents

- Before implementing, reconcile this target doc with `docs/for-you-legacy.md` and remove stale references to files that no longer exist or are not restored.
- Keep recommendations local and provider-scoped.
- If watch progress or favorites are added for For You, update `favorites.md`, `media-details.md`, `video-player.md`, and `library-sync-local-data.md`.
