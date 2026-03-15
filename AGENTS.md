# Repository Guidelines

## Project Structure & Module Organization
The app target lives in `iptv/`, organized by responsibility:
- `Client/` for networking (`HTTPClient.swift`, `Xtream/`, `TMBD/` services and models).
- `Model/` for domain types, mapping, and preview data (`Model/Data/`, `Model/Preview/`).
- `UI/Screens/` and `UI/Views/` for SwiftUI screens and reusable components.
- `Player/` for playback integrations (`AVKit`, `VLCKit`) and window-level player UI.
- `Assets.xcassets/` for icons and color assets.

Tests are split by type: `iptvTests/` (unit tests) and `iptvUITests/` (UI tests). Project settings and SwiftPM resolution are in `iptv.xcodeproj/`.

## Catalogue Architecture Notes
- `CatalogueStore` is the single runtime source of truth for catalogue categories, cached streams, refresh state, search queries, and bootstrap sync progress.
- `Catalog` is a `@MainActor` facade for SwiftUI-facing state only. Keep network fetches, SwiftData reconciliation, and sync bookkeeping out of `Catalog` when adding new work.
- Search now reads persisted catalogue data directly. Do not add new runtime dependencies on `SearchIndexStore`; treat legacy search snapshot/index tables as migration leftovers only.
- Background catalogue refresh is intentionally single-flight and low-priority. Prefer one shared datastore write path for both foreground cache misses and background refreshes.
- Cached category hits should return immediately without triggering refresh. Only missing categories should fetch on demand.
- Settings should show bootstrap coverage only, based on categories that have been synced at least once (`lastSuccessfulRefreshAt != nil`). Continuous refresh status belongs in the background activity UI, not Settings.

## Persistence Notes
- SwiftData is the only source of truth for app persistence. Do not add new disk-backed JSON/file persistence for favorites, watch activity, catalogue/search cache, downloads, or offline metadata rows.
- Keep app-facing wrappers and services named `...Store`. Use `...Persistence` for raw SwiftData collaborators and `@ModelActor` database actors.
- Do not pass SwiftData `@Model` instances across actor boundaries or into SwiftUI state. Map persisted entities to plain Swift value types before returning them.
- When adding persistence APIs, prefer provider-scoped queries, `fetchCount` for existence checks, unique-key upserts, and batch deletes instead of fetch-then-delete loops.
- Keep disk usage only for true file assets such as downloaded media or artwork blobs, not structured app state.

## Build, Test, and Development Commands
- `open iptv.xcodeproj`: open the project in Xcode for local development.
- `xcodebuild -project iptv.xcodeproj -scheme iptv -configuration Debug build`: CLI build.
- `xcodebuild -project iptv.xcodeproj -scheme iptv -destination 'platform=macOS' test`: run tests on macOS.
- `xcodebuild -project iptv.xcodeproj -scheme iptv -destination 'platform=iOS Simulator,name=iPhone 16' test`: run simulator tests.

Use the `iptv` scheme for app + test workflows.

## Coding Style & Naming Conventions
Use Swift conventions visible in the codebase:
- 4-space indentation and one primary type per file.
- `UpperCamelCase` for types, `lowerCamelCase` for methods/properties, `lowerCamelCase` for enum cases.
- Name SwiftUI screens with `...Screen` and reusable views with `...View`/`...Tile`.
- Keep networking logic in `Client/*Service.swift`; keep presentation logic in `UI/`.

No repo-level lint config is present, so use Xcode formatting and keep style consistent with nearby files.

## Testing Guidelines
- Unit tests currently use Swift Testing (`import Testing`, `@Test`) in `iptvTests/`.
- UI tests use XCTest in `iptvUITests/` with `test...` methods.
- Prefer test file names like `FeatureNameTests.swift`.
- Add or update tests for mapper/service logic and critical UI flows before merging.

## Commit & Pull Request Guidelines
Git history is not available in this workspace snapshot, so use Conventional Commits:
- `feat(player): add VLC fallback`
- `fix(client): handle missing category id`

PRs should include a short summary, linked issue (if any), test evidence (commands/device), and screenshots for UI changes.

## Security & Configuration Tips
- Do not commit real provider credentials or private endpoints.
- `VLCKit.xcframework` is referenced via a local path in the project; keep local dependency setup documented in PRs when changing it.
