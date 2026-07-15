# Feature: Library and Search

## Purpose

Provide fast local discovery across the synchronized movie and series catalog without routine remote queries.

## Status

Implemented for local movie/series title and metadata search, scope selection, category/group/rating filters, deterministic sorts, hidden-prefix rules, favorites/resume indicators, partial-hydration disclosure, and detail navigation. Filtering runs from Sendable snapshots in a cancellable background task.

## User Experience

The Search tab starts with a prompt, shows truthful empty and partial-coverage states, and updates results after a short typing debounce. Existing results remain visible while a replacement computation runs. Users can switch between All, Movies, and Series and clear query/filter combinations independently.

## Data and State

Search operates on locally persisted `Media` and `Category` rows. `LibraryFilterRequest` is a Sendable worker snapshot; the separate compact `LibraryFilterTaskID` contains normalized criteria, included media types, and a catalog revision without complete row arrays. `LibraryFilterEngine.filteredMedia(inBackground:)` performs normalization, scope matching, filtering, and sorting off the main actor and propagates cancellation to its detached worker. `LibrarySearchIndexes` provides category, active-profile favorite, and resume lookups. Search skips result computation while no query or filter is active.

## Key Files

- `iptv/UI/Screens/SearchScreen.swift`
- `iptv/Model/LibraryFilters.swift`
- `iptv/Model/Database/Schema.swift`

## Target Acceptance Criteria

- Search remains responsive for large local catalogs.
- Stale/cancelled computations never replace newer results.
- Movies and series respect the same hidden categories and filter semantics as Browse.
- Favorites and resume badges use only the active provider/profile.
- Partial local hydration is disclosed instead of implying complete results.

## Current Gaps / Planned Work

- Relevance ranking is deterministic title/metadata matching rather than a persisted FTS index.
- Episode search is reached through series details; Live has its own local search surface.
- Add an FTS table only if measured catalog sizes exceed snapshot-filter performance.

## Notes for Agents

Do not introduce a remote request per keystroke. Keep `LibraryFilterRequest` Sendable, keep row arrays out of SwiftUI task identity, and commit results only after cancellation checks. Any future persisted search history must be profile scoped.
