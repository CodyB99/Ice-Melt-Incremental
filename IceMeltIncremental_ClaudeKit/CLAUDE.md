# Ice Melt Incremental — Project Instructions

## Mission
Build a polished, secure, mobile-first Roblox incremental game whose core loop is:

**move through ice → crack/melt ice → earn Heat → upgrade power/radius/value → unlock tools and zones → discover frozen secrets → Thaw for Embers → repeat faster**

The commercial goal is a small, shippable MVP that can test retention and monetization quickly. Favor reliable systems, satisfying feedback, and measurable onboarding over feature count.

## Read before editing
Always read these files when relevant:

- `PROJECT_STATUS.md`
- `docs/01_GAME_DESIGN.md`
- `docs/02_TECHNICAL_ARCHITECTURE.md`
- `docs/03_ECONOMY_AND_BALANCE.md`
- `docs/04_CONTENT_CATALOG.md`
- `docs/05_MONETIZATION.md`
- `docs/06_UI_UX.md`
- `docs/07_ART_AUDIO_ASSETS.md`
- `docs/08_ANALYTICS.md`
- `docs/09_QA_RELEASE.md`

## Non-negotiable scope
MVP includes exactly three zones, eight tools, Heat, Embers, seven upgrade tracks, one Thaw layer, twenty discoveries, onboarding, saving, analytics, passes, and developer products.

Do not add pets, eggs, trading, clans, PvP, crafting, multiple places, procedural infinite worlds, or extra currencies unless the owner explicitly changes scope after launch data.

## Engineering rules

- Use Luau `--!strict` in production modules and scripts.
- Keep the server authoritative for currency, damage, unlocks, upgrades, Thaws, discoveries, rewards, and purchases.
- Never trust client-supplied reward amounts, upgrade levels, positions, radii, tool stats, prices, or ownership.
- Clients may request an action and render predicted visuals; the server validates and commits state.
- Use small focused services/modules with explicit dependencies. Avoid circular requires and global mutable tables.
- Use attributes, CollectionService tags, configuration modules, and object pooling instead of repeated hard-coded paths.
- Use `UpdateAsync`-based versioned persistence, autosave, retries, a session token/lock, and safe shutdown handling.
- Developer product receipts must be idempotent and processed in one server-owned `MarketplaceService.ProcessReceipt` callback.
- Display live marketplace prices; never hard-code Robux prices in UI.
- Avoid external packages for the MVP unless they remove substantial risk and are documented in `DECISIONS.md`.
- Keep ordinary MVP values below roughly `1e15`; use a shared number formatter rather than adding a BigNum system.
- All remotes must have type, rate, state, and plausibility validation.
- No free model scripts may enter the project without inspection.

## Workflow rules

- Execute one phase at a time from `prompts/`.
- Before coding, state the files/systems you will change and list unresolved assumptions.
- After coding, run available format/lint/build checks, inspect Studio Output, and play-test through Studio MCP when possible.
- Do not claim a test passed unless it was actually run. Record blocked tests.
- Update `PROJECT_STATUS.md`, `DECISIONS.md`, and relevant documentation after each phase.
- Preserve working behavior. Prefer a small vertical slice over broad unfinished scaffolding.
- Commit-ready changes must contain no placeholder `TODO` in a required acceptance path.

## Definition of done for any phase

1. Acceptance criteria in the phase prompt are met.
2. Server/client boundaries are secure.
3. Failures produce actionable warnings, not silent corruption.
4. Mobile UI and performance implications are considered.
5. Relevant tests are run and reported.
6. Project status is updated with exact evidence and remaining blockers.
