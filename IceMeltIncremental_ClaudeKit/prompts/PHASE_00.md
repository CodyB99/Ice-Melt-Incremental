# Phase 00 — Repository and Studio Setup

## Objective
Create a reproducible Rojo project connected to the open Roblox Studio experience and establish the expected DataModel, tags, folders, environment flags, and testing workflow.

## Tasks

- Read all project documentation.
- Verify `default.project.json`, Rojo connection, and source sync.
- Verify Roblox Studio MCP connection and list the relevant Studio tools available.
- Create/verify server-created runtime folders for remotes and replicated state rather than relying on manual objects.
- Create a simple Studio world skeleton: Spawn, hub signage, zone placeholders, safe boundaries, and folders/tags described in the architecture.
- Add environment configuration for Development/Test/Production data store names and debug flags.
- Ensure the Bootstrap scripts run without errors and print a single development-only startup line.
- Build the project and inspect Studio Output.
- Document exact local commands and any unavailable tools.

## Acceptance criteria

- Rojo changes appear in Studio.
- Claude can inspect the open DataModel through MCP.
- Play mode starts with no red errors.
- Environment mode is explicit and production data cannot be selected accidentally in ordinary Studio tests.
- `PROJECT_STATUS.md` records evidence and setup blockers.
