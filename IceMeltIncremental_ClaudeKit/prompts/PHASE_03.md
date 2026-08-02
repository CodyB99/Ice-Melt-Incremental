# Phase 03 — Ice Field and Melt Vertical Slice

## Objective
Deliver the first genuinely playable loop: spawn, walk/aim through ice, crack it, melt it, earn server-authoritative Heat, and see cells respawn.

## Tasks

- Build the Backyard ice field from configuration using chunks/pooling.
- Implement cell durability, crack stages, melted state, respawn, and batch updates.
- Implement rate-limited melt pulse requests where the server derives position, tool stats, radius, zone, eligible cells, damage, crits, and Heat.
- Add client prediction/effects that never grant currency.
- Add pooled crack/steam/reward feedback and aggregated sound behavior.
- Add server caps on cells, damage, rewards, sequence replay, and pulse frequency.
- Add a small development overlay for pulse count/rejections and active cells.

## Acceptance criteria

- First melt occurs within five seconds.
- Heat only changes through server mutations.
- Remote spam and impossible position requests are rejected/rate-limited.
- A batch/chain does not generate one remote per cell.
- Cells respawn without sustained create/destroy churn.
- Two-player test shows consistent authoritative results.
