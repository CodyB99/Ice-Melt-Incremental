---
description: Audit a completed Ice Melt Incremental phase against security, design, tests, and acceptance criteria.
argument-hint: "[phase number, such as 03]"
disable-model-invocation: true
---

Read `CLAUDE.md`, `PROJECT_STATUS.md`, the matching phase prompt under `prompts/`, and all changed code relevant to `$ARGUMENTS`.

Perform an adversarial review. Inspect server/client trust boundaries, data integrity, lifecycle cleanup, mobile implications, configuration duplication, errors, and untested claims. Use Roblox Studio MCP to inspect Output and run the most relevant tests.

Fix clear defects that are within the phase scope. Do not add deferred features. Update `PROJECT_STATUS.md` with review evidence.

Report findings ordered by severity, fixes made, tests actually run, remaining blockers, and whether the phase is approved to proceed.
