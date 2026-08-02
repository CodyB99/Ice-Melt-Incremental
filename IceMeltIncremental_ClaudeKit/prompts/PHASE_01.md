# Phase 01 — Shared Contracts and Bootstrapping

## Objective
Create the strict typed contracts, configuration modules, remote registry, service lifecycle, and controller lifecycle used by every later phase.

## Tasks

- Implement shared types for player profile, replicated state, tools, zones, upgrades, discoveries, melt requests/results, and receipts.
- Implement configuration modules using the documented baseline values.
- Add remote names/schema and server-owned remote creation.
- Implement deterministic service initialization/start order and client controller startup.
- Add a shared number formatter and validation utilities.
- Add development assertions for duplicate service names, invalid config references, and malformed IDs.
- Do not implement gameplay yet beyond a safe handshake and state-ready signal.

## Acceptance criteria

- All Luau files are strict and typecheck as far as available tooling permits.
- Server creates only expected remotes.
- Client cannot invoke unregistered generic command remotes.
- Start order is logged once in development and has no race-condition waits without timeouts.
- Build/play test has no red errors.
