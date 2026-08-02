# Phase 02 — Persistence and Player State

## Objective
Implement durable, versioned player profiles with session safety and sanitized replicated state.

## Tasks

- Implement default profile and schema migrations.
- Load via UpdateAsync with retries/backoff and session token/lock behavior.
- Validate and repair missing/invalid fields.
- Add autosave, PlayerRemoving release, and BindToClose handling.
- Prevent gameplay until profile load succeeds; provide a user-safe failure path.
- Add `PlayerStateService` getters/mutations that do not expose mutable profile tables.
- Replicate a sanitized snapshot/delta to the owning client.
- Add development-only data reset/testing commands gated to owner/test environment.

## Acceptance criteria

- New player gets correct defaults.
- Leave/rejoin preserves a test mutation.
- Two sessions cannot silently overwrite the same profile.
- Invalid fields are repaired and logged.
- Full profile and receipt history never replicate to clients.
- No production store is touched in Studio.
