# Economy and Balance Baseline

All numbers are initial tuning values. Put live values in configuration modules so they can be changed without rewriting services.

## Currency

- **Heat:** run currency, reset by Thaw.
- **Embers:** permanent prestige currency, retained by Thaw.

## Upgrade curves

Use `floor(baseCost * growth^(level))` unless otherwise stated.

| Upgrade | Base effect | Base cost | Growth | Effect per level | Cap |
|---|---:|---:|---:|---:|---:|
| Power | 10 damage/sec | 15 | 1.32 | ×1.16 | 100 |
| Radius | 4.5 studs | 60 | 1.55 | +0.45 stud | 45 |
| Heat Value | ×1.00 | 25 | 1.38 | ×1.12 | 100 |
| Walk Speed | 16 | 100 | 1.70 | +0.75 | 20 levels / 31 speed |
| Crit Chance | 3% | 250 | 1.65 | +0.5% | 25% |
| Discovery Luck | ×1.00 | 500 | 1.75 | ×1.08 | 40 |
| Auto-Melt | 0 pulses/sec | 2,500 | 1.80 | +0.10 pulse/sec | 20 |

Critical melts grant 3× Heat. Cap all final multipliers and document the order of operations.

## Tools

| # | Tool | Unlock Heat | Power multiplier | Radius bonus |
|---:|---|---:|---:|---:|
| 1 | Match | 0 | 1.00 | 0 |
| 2 | Candle | 350 | 1.35 | 0.25 |
| 3 | Torch | 2,500 | 1.85 | 0.50 |
| 4 | Blowtorch | 18,000 | 2.60 | 0.75 |
| 5 | Flamethrower | 125,000 | 3.80 | 1.25 |
| 6 | Heat Cannon | 900,000 | 5.80 | 1.75 |
| 7 | Lava Core | 8,000,000 | 9.00 | 2.50 |
| 8 | Mini Sun | 85,000,000 | 15.00 | 4.00 |

## Zones

| Zone | Unlock cost | Base cell durability | Base Heat | Respawn | Discovery multiplier |
|---|---:|---:|---:|---:|---:|
| Frozen Backyard | 0 | 10 | 1 | 5 sec | 1.0 |
| Ice Cavern | 25,000 | 250 | 30 | 7 sec | 1.5 |
| Frozen City | 5,000,000 | 12,000 | 1,800 | 9 sec | 2.25 |

Use cell variants and clusters to avoid every tile feeling identical.

## Thaw

Initial requirement: `1,000,000 LifetimeHeatThisRun`.

Suggested Ember award:

`max(1, floor((RunHeat / 1_000_000) ^ 0.55))`

Suggested permanent production multiplier:

`1 + (TotalEmbers ^ 0.65) * 0.15`

Reset: Heat, run upgrades, unlocked tools, zones beyond Backyard, and run counters.

Keep: Embers, Thaws, discoveries, settings, rewards, purchases, and permanent Ember nodes.

## Pacing review

After the first complete vertical slice, simulate and play-test:

- First upgrade: 15–30 seconds
- Candle: 2–4 minutes
- Ice Cavern: 8–12 minutes
- First Thaw: 20–30 minutes

Do not tune from formulas alone. Record actual playtest timestamps in `PROJECT_STATUS.md`.
