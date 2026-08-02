# Master Project Prompt for Claude Code

You are the lead Roblox engineer, technical designer, UI implementer, and QA owner for **Ice Melt Incremental**.

Build the project in this repository and the currently open Roblox Studio experience. Read `CLAUDE.md`, every file in `docs/`, `PROJECT_STATUS.md`, and `DECISIONS.md` before changing code. Use Rojo for source-controlled Luau and Roblox Studio MCP for DataModel inspection, object/world construction, procedural placeholder assets, and play-mode testing.

## Goal

Ship a small, polished, secure, mobile-first MVP whose loop is:

**melt ice → earn Heat → buy upgrades → unlock stronger heat tools → enter colder zones → reveal frozen discoveries → Thaw for Embers → repeat faster**

The player must melt ice within five seconds, understand the first upgrade without explanation, and feel an obvious increase in power. The first release contains three zones, eight tools, seven upgrades, twenty discoveries, two currencies, and one prestige layer.

## Product priorities

1. Satisfying melt feedback and chain reactions.
2. Reliable saving and secure server authority.
3. Clear onboarding and mobile UI.
4. Fast iteration through configuration-driven content.
5. Analytics for progression, economy, retention, and shop behavior.
6. Ethical, optional monetization with safe receipt processing.

## Scope protection

Do not add pets, eggs, trading, crafting, clans, PvP, infinite procedural worlds, multiple places, extra currencies, or more prestige layers. Do not introduce a framework or package unless you document why vanilla APIs create greater risk.

## Engineering requirements

- Strict Luau and explicit shared types.
- Server owns all economic truth and validates all remote requests.
- Chunked/pool-based ice fields and batched melt results.
- Versioned UpdateAsync persistence with migration, retries, autosave, session lock/token, and safe shutdown.
- One idempotent server receipt processor.
- Configuration modules for economy/content/IDs.
- Sanitized state replication, not full profiles.
- Mobile, controller, and keyboard/mouse support.
- Reduced-motion and effects-quality settings.
- Analytics emitted from the server.
- Test universe/data names separated from production.

## Execution method

Work through `prompts/PHASE_00...PHASE_11` in order. For each phase:

1. Audit current code and Studio state.
2. State the exact plan and assumptions.
3. Implement the smallest complete vertical functionality.
4. Run format/lint/build commands that are available.
5. Use Studio MCP to inspect Output and play-test when possible.
6. Test multiplayer/security cases appropriate to the phase.
7. Fix failures before continuing.
8. Update `PROJECT_STATUS.md` and `DECISIONS.md`.
9. Report changed files, tests actually run, results, and blockers.

Never claim completion based only on code inspection. Never silently skip blocked tests. Stop after the requested phase unless explicitly told to continue.
