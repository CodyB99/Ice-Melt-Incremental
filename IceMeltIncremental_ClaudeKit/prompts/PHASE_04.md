# Phase 04 — Economy, Upgrades, and Tools

## Objective
Turn the melt slice into an incremental progression loop with seven upgrades and eight tool unlocks.

## Tasks

- Implement authoritative cost/effect functions and caps.
- Implement purchase requests with balance, level, prerequisite, and replay validation.
- Recompute derived stats in one server module and replicate only final UI fields.
- Implement tool unlock/equip validation and eight configured tools.
- Build placeholder tool models/icons/effects using Studio MCP or primitives.
- Add UI for Heat, upgrade cards, next tool, affordability, and clear before/after feedback.
- Add number formatting and test boundary values.

## Acceptance criteria

- First upgrade is reachable in 15–30 seconds during playtest.
- Candle is reachable in roughly 2–4 minutes using baseline tuning or documented adjustment.
- Client cannot buy free/negative upgrades or equip locked tools.
- Tool changes visibly alter melt behavior.
- Costs and effects come from shared configuration, not duplicated magic numbers.
