# Technical Architecture

## Runtime model

Use a service/controller architecture with configuration-driven content.

### Shared modules

- `Types`
- `GameConfig`
- `BalanceConfig`
- `ContentConfig`
- `MonetizationConfig`
- `RemoteNames`
- `NumberFormatter`
- small validation/math utilities

### Server services

- `DataService` — load, lock, migrate, autosave, release profiles
- `PlayerStateService` — authoritative runtime state and replication snapshots
- `MeltService` — validates pulses, applies damage, commits rewards
- `IceFieldService` — zone cells, respawn, pooling, crack state
- `EconomyService` — grants/spends Heat and Embers
- `UpgradeService` — costs, caps, stat recomputation
- `ToolService` — unlock/equip validation
- `ZoneService` — gate purchases and travel validation
- `ThawService` — reset and permanent progression
- `DiscoveryService` — weighted rolls, collection state, rewards
- `RewardService` — daily, playtime, codes
- `MonetizationService` — pass checks, price info, prompts, receipts
- `GameAnalyticsService` — funnel/economy/custom events from server

### Client controllers

- `InputController`
- `MeltEffectsController`
- `HUDController`
- `UpgradeUIController`
- `ShopUIController`
- `OnboardingController`
- `ZoneController`
- `AudioController`
- `AccessibilityController`

## Melt protocol

The client may request a heat pulse with a sequence number and local intent. The server must derive the player's actual character position, equipped tool, power, radius, cooldown, zone, and eligible cells.

Validation must include:

- player/profile is loaded
- character and HumanoidRootPart exist
- requested sequence is newer
- server cooldown/token bucket allows the pulse
- player is in the claimed zone
- cells are within server-calculated radius
- tool/upgrade stats come from authoritative state
- maximum cells and reward per pulse are capped

The server returns compact melt results for visuals. Do not send one remote per tile when batching is possible.

## Ice representation

Use chunked grid cells with pooling. Each zone has configuration for dimensions, spacing, durability, value, respawn, discovery odds, and visuals.

MVP performance principle:

- Avoid creating/destroying parts continuously.
- Reuse cells and effects.
- Batch state changes.
- Keep collision/query configuration minimal.
- Use CollectionService tags and attributes.
- Prefer client-only particles/audio over replicating transient effect objects.

## Data profile

Versioned schema example:

```luau
{
    SchemaVersion = 1,
    Heat = 0,
    LifetimeHeat = 0,
    Embers = 0,
    Thaws = 0,
    Upgrades = { Power = 0, Radius = 0, Value = 0, Speed = 0, Crit = 0, Luck = 0, Auto = 0 },
    HighestTool = 1,
    EquippedTool = 1,
    UnlockedZones = { Backyard = true },
    Discoveries = {},
    RewardState = {},
    Settings = {},
    ReceiptHistory = {},
}
```

Use migration functions, sane defaults, validation on load, and a per-session token. Never save Instances, userdata, connections, or unbounded receipt history.

## Replication

Do not replicate the full mutable profile table. Replicate a sanitized player state snapshot/delta containing only UI-relevant fields. Keep receipt history and anti-exploit counters server-only.
