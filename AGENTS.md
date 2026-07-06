# General Application Functionality

## Overview
`iptv` is a native SwiftUI IPTV client for Apple platforms. The app connects to a remote Xtream provider, replicates the remote library into local SwiftData storage, and renders the UI from that local database for fast browsing, search, and playback.

## Specification
- Canonical feature specs live directly in `docs/` as Markdown files.
- Use these docs to restore target-state context across agent runs and to develop features in isolation.
- A feature is documented as one single feature even when it spans multiple parts of the codebase, such as UI, sync, persistence, search, and playback.
- Prefer updating an existing feature doc over creating a narrower duplicate.

Every feature spec must use this exact section order:
1. `# Feature: <Name>`
2. `## Purpose`
3. `## Status`
4. `## User Experience`
5. `## Data and State`
6. `## Key Files`
7. `## Target Acceptance Criteria`
8. `## Current Gaps / Planned Work`
9. `## Notes for Agents`

When adding or updating a feature spec:
- Describe the target state first, then clearly separate current implementation from planned gaps.
- Ground implementation notes in concrete files, symbols, or existing docs.
- Keep cross-cutting behavior in the one feature doc rather than splitting it by subsystem.
