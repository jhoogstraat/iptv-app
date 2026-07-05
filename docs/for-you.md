# Feature: For You

## Purpose

For You is the landing and discovery experience. It should make the app feel like a local media library by surfacing continue watching, personalized recommendations, trending content, and new additions from locally synced state.

## Status

- Target state: For You renders a personalized local discovery page using provider-scoped catalog data and watch activity.
- Current implementation: the active `ForYouScreen` is a placeholder saying the personalized landing screen is being migrated to SQLiteData. Reusable For You view components exist under `iptv/UI/Views/ForYou/`. Browse/search prefix visibility is implemented, but no recommendation query consumes it yet. An older detailed document exists at `docs/for-you-legacy.md` and should be reconciled before implementation resumes.
- Current navigation: `ContentView` currently inlines a For You placeholder instead of presenting `ForYouScreen`.

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
- Current active schema does not expose watch progress, favorites, or recommendation persistence.
- Existing UI components include hero, rail, and continue-watching card views.

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
- Watch activity persistence is not present in the current schema.
- Recommendation model/provider files referenced by older docs are not visible in the current file tree.
- Prefix visibility is available for browse/search and must be applied to recommendation queries once For You is backed by local data.

## Notes for Agents

- Before implementing, reconcile this target doc with `docs/for-you-legacy.md` and remove stale references to files that no longer exist or are not restored.
- Keep recommendations local and provider-scoped.
- If watch progress or favorites are added for For You, update `favorites.md`, `media-details.md`, `video-player.md`, and `library-sync-local-data.md`.
