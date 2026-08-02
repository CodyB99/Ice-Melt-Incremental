# Game Design Specification

## Product promise

**Melt ice, reveal frozen secrets, upgrade your heat, and Thaw entire worlds.**

The game must be understandable without reading. A new player should spawn facing meltable ice, see it crack immediately, receive Heat, and be pointed to the first affordable upgrade.

## Audience and session goals

- Mobile-first, broad Roblox simulator/incremental audience.
- First melt: under 5 seconds.
- First upgrade: 15–30 seconds.
- First tool unlock: 2–4 minutes.
- Zone 2: 8–12 minutes.
- First Thaw: 20–30 minutes for an engaged new player.
- MVP target session: 12–20 minutes, then tune with live analytics.

These are design targets, not guaranteed outcomes.

## Core loop

1. Player moves through or aims a heat radius at ice cells.
2. Cells show crack stages, melt, play layered audio, and grant Heat.
3. Heat buys seven upgrade tracks and unlocks tools/zones.
4. Rare cells reveal discoveries and occasional chain reactions.
5. Player reaches the Thaw requirement and resets run progression.
6. Embers permanently increase future runs and unlock quality-of-life nodes.

## Seven upgrade tracks

1. Melt Power
2. Melt Radius
3. Heat Value
4. Walk Speed
5. Critical Melt Chance
6. Discovery Luck
7. Auto-Melt Rate

Auto-Melt must also be earnable through progression. A pass may improve it but cannot be the only access.

## Feel pillars

- **Immediate:** no click delay or confusing equipment step.
- **Visible:** cracks, steam, shrink/dissolve, clean paths, reward bursts.
- **Escalating:** one tile becomes clusters, then chain reactions and fields.
- **Curious:** discoveries answer “what is frozen inside?”
- **Readable:** one primary currency, clear next goal, limited simultaneous popups.

## MVP content boundaries

- 3 zones
- 8 tools
- 20 discoveries
- 7 upgrade tracks
- 1 prestige layer
- Daily reward, playtime reward, simple codes
- No pets, trading, crafting, clans, PvP, or multiple places

## Failure conditions

The MVP is not ready if melting feels delayed, visual changes are hard to see, the next purchase is unclear, mobile UI covers gameplay, or progress can be lost/duplicated.
