# Phase 05 — Three Zones and Travel

## Objective
Build Frozen Backyard, Ice Cavern, and Frozen City as readable progression spaces with validated unlocks and travel.

## Tasks

- Construct performant placeholder worlds through Studio MCP, using the art specification.
- Add zone-specific ice configuration, ambience, lighting accents, props, boundaries, and spawn/travel points.
- Implement server-authoritative zone unlock purchases and travel validation.
- Keep the player from melting cells outside the active/valid zone.
- Add zone UI, locked gate feedback, next-zone preview, and return travel.
- Use tags/attributes rather than brittle paths.

## Acceptance criteria

- All three zones are visually distinct and traversable on mobile.
- Cavern unlock playtest target is 8–12 minutes or adjustment is documented.
- Locked travel cannot be forced by client remotes or teleporting character state alone.
- Zone switching does not leak old fields/effects or multiply loops.
- Largest zone maintains acceptable performance in a multiplayer test.
