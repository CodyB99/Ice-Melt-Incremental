# Phase 07 — Discoveries and Chain Reactions

## Objective
Add curiosity and spectacle through twenty saved discoveries, rarity feedback, and capped chain reactions.

## Tasks

- Implement weighted server rolls adjusted by zone/luck with normalized probabilities.
- Associate discoveries with valid zones and collection state.
- Award/save before showing reveal UI.
- Build collection index, silhouette states, zone completion, and rarity labels/icons.
- Add Heat Pocket, Lava Capsule, and Unstable Reactor chain objects.
- Implement server-authoritative chain propagation and hard reward/cell caps.
- Add audio/effect aggregation and reduced-motion behavior.

## Acceptance criteria

- All twenty discoveries are obtainable only in valid zones.
- Duplicate discovery behavior is explicitly designed and tested.
- Luck cannot exceed configured caps or create invalid weights.
- Large chains remain performant and cannot be replayed for duplicate rewards.
- Legendary/Secret announcements reveal no sensitive data and are rate-limited.
