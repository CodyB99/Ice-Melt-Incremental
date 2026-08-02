# Phase 10 — Analytics, Security, and Performance

## Objective
Instrument the MVP, attack its trust boundaries, and make it performant enough for release testing.

## Tasks

- Implement documented funnel, economy, and custom server events.
- Add development diagnostics for remote rejection categories, save failures, and performance fallback.
- Perform exploit attempts listed in QA docs and fix issues.
- Profile largest field, chain, UI, network, particles, sounds, and multiplayer behavior.
- Add adaptive effect quality and sensible low-end limits.
- Remove noisy logs and development-only interfaces from production mode.
- Run a 30-minute multiplayer soak or document why it is blocked.

## Acceptance criteria

- Analytics calls fail safely and never block gameplay.
- No tested remote can mint currency, bypass gates, duplicate rewards, or corrupt state.
- Pooling/batching prevents sustained instance/network spikes.
- Low effects mode remains readable.
- All known red errors and high-severity warnings are resolved.
