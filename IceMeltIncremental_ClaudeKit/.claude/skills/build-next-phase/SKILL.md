---
description: Execute one requested Ice Melt Incremental phase with implementation, tests, and status updates.
argument-hint: "[phase number, such as 03]"
disable-model-invocation: true
---

Read `CLAUDE.md`, `PROJECT_STATUS.md`, and the phase file matching `$ARGUMENTS` under `prompts/`. Also read every linked design document relevant to that phase.

Execute only that phase. Before editing, inspect existing code and the open Studio experience, then state the change plan and assumptions. Implement the acceptance criteria, run available format/lint/build checks, inspect Studio Output, and use Roblox Studio MCP for play testing whenever possible.

Fix failures before reporting completion. Update `PROJECT_STATUS.md` and `DECISIONS.md`. End with:

- changed files and Studio objects
- tests actually run and exact results
- acceptance criteria status
- blockers and owner actions
- the next phase, but do not start it
