---
description: Inspect and test the Ice Melt project in the currently open Roblox Studio session through MCP.
disable-model-invocation: true
---

Connect to the Roblox Studio MCP server. Verify the expected DataModel, read relevant scripts, inspect Output, run play mode, and test the current vertical slice.

Prioritize:

- red errors and warnings
- missing/tampered tags or attributes
- duplicate loops/connections after respawn
- remote validation
- player data readiness
- mobile/controller UI state
- ice field performance and effect pooling

Do not claim a test passed if MCP cannot run it. Record exact evidence in `PROJECT_STATUS.md`.
