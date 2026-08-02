# Art, Audio, and Asset Plan

## Visual direction

Stylized, bright, readable, and toy-like rather than photorealistic. Use strong warm-vs-cold contrast: blue/cyan ice environments against orange/yellow/red heat effects.

Do not rely on color alone for rarity or interactability.

## Quick-build asset strategy

Use Roblox Studio primitives, built-in materials, generated procedural models, and simple custom UI shapes for the first vertical slice. Replace only the highest-impact assets before release.

Claude may use Studio MCP to:

- generate primitive/procedural tool placeholders
- create environmental props
- generate material variants
- search Creator Store assets
- inspect the DataModel and scripts
- run play-mode tests

Every externally sourced asset must be recorded in `ASSET_MANIFEST.csv` and inspected for scripts.

## Required custom/high-impact assets

- game icon
- 3–5 thumbnails
- logo/title treatment
- eight tool icons
- seven upgrade icons
- discovery silhouettes/cards
- core crack, hiss, melt, unlock, rarity, and chain audio
- polished Mini Sun and Lava Core hero models/effects

## Audio rules

- Short, layered, and rate-limited.
- Randomize pitch/variant slightly to prevent repetition fatigue.
- Do not play one sound per tile during large chains; aggregate by burst size.
- Respect user volume settings.

## Thumbnail concepts

1. Small Match melting a path toward a giant Mini Sun.
2. Before/after frozen city split with a huge chain reaction.
3. Secret alien object revealed inside cracked ice.

Use large readable forms and no tiny UI text.
