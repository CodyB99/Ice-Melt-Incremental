# Project Status

Updated: 2026-08-02

## Phase checklist

- [x] 00 — Repository, Rojo, Studio MCP, and DataModel setup
- [x] 01 — Shared types, configuration, remotes, and bootstrapping
- [x] 02 — Player data, session safety, and replicated state
- [x] 03 — Ice fields, server-authoritative melt loop, and pooling
- [ ] 04 — Heat economy, upgrades, tool progression, and number formatting — ⚠️ built and secure; Candle pacing target not met
- [ ] 05 — Three zones, gates, world construction, and travel — ⚠️ built and secure; Cavern pacing target not met, multiplayer performance not run
- [ ] 06 — Thaw prestige and permanent Ember progression — ⚠️ built and secure; first-Thaw pacing target not met
- [ ] 07 — Frozen discoveries, rarity, collection index, and chain reactions
- [ ] 08 — UI, onboarding, feedback, rewards, codes, and accessibility
- [ ] 09 — Passes, developer products, shop, and safe receipts
- [ ] 10 — Analytics, exploit hardening, performance, and device QA
- [ ] 11 — Release candidate, thumbnails checklist, live configuration, and launch

## Experience identity

| Field | Value |
|---|---|
| Place name | IceMeltIncremental |
| PlaceId | 87210191828303 |
| GameId / universe | 10620948462 |
| Registered in `EnvironmentConfig` as | **Test** (not Production) |

Registered as Test on purpose. `PRODUCTION_PLACE_IDS` is still empty, so no server
anywhere can reach the production data store yet. Move the PlaceId only when this place
becomes the live experience.

## Current vertical slice

No gameplay yet, by design — Phase 00 is setup only.

The server now builds a placeholder world at runtime from configuration:

- `Workspace.IceMelt` with `Zones`, `Hub`, `Effects`
- Three zone folders (Backyard, Cavern, City), each with `Ground`, four boundary walls,
  `IceField`, `Props`, `Markers/ZoneSign`
- `Hub/Spawn` (the only enabled SpawnLocation) and `Hub/Signage/TitleSign`
- Zone attributes mirrored from `ContentConfig`, tags from `TagNames`

Nothing is hand-placed in the Explorer, so the world is reproducible from source control.

## Test evidence

All results below were produced on 2026-08-02 by running the commands, not by inspection.

| Phase | Command / test | Result |
|---|---|---|
| 00 | `rojo build default.project.json -o IceMeltIncremental.rbxlx` | **Pass** after fix. Failed first: `IceMelt` node had no `$className` |
| 00 | `stylua --check src` | **Pass** (clean) |
| 00 | `luau-lsp analyze` over `src` (10 files) | **Pass**, exit 0. Failed first: one union-narrowing error in `EnvironmentConfig` |
| 00 | `selene src` | **Pass** — 0 errors, 0 warnings, 0 parse errors. Runs offline against the committed `roblox.yml`. Its first run caught a real defect: duplicate `if`/`else` branches in `EnvironmentConfig`, since removed |
| 00 | Rojo sync into Studio (port 34873) | **Pass**. `ReplicatedStorage.IceMelt.Shared.Config` (8 modules + `Types`), `ServerScriptService.IceMeltServer` (Bootstrap + Runtime + World), `StarterPlayerScripts.IceMeltClient.Bootstrap`. Nothing missing |
| 00 | Studio MCP DataModel inspection | **Pass** — Edit and Server datamodel reads, console reads, play control, screen capture all worked |
| 00 | Play mode, Output check | **Pass** — no red errors. Exactly two startup lines plus one expected warning (see below) |
| 00 | Runtime containers created by server | **Pass** — `ReplicatedStorage.IceMelt.Remotes`, `.State`, `ServerStorage.IceMelt.Pools`, `Workspace.IceMelt` all present as Folders |
| 00 | Zone attributes match `ContentConfig` | **Pass** — all three zones: ZoneKey, ZoneIndex, DisplayName, UnlockCost, BaseDurability, BaseHeat, RespawnSeconds, LuckMultiplier |
| 00 | CollectionService tags | **Pass** — WorldRoot 1, Zone 3, ZoneGround 3, IceField 3, Boundary 12, Spawn 1, Sign 4 |
| 00 | `WorldSkeleton.build` idempotency | **Pass** — 51 descendants before; identical class counts after two extra rebuilds; zero duplicates |
| 00 | Foreign SpawnLocation handling | **Pass** — template spawn disabled with a warning; `EnabledForeignSpawns = 0` |
| 00 | Studio → production data store guard | **Pass by construction, not yet exercised on a live server.** `EnvironmentConfig` resolved `Development` / `IceMelt_PlayerData_DEV_v1` in Studio |

Exact Output from the play test:

```
[IceMelt] WorldSkeleton: disabled foreign SpawnLocation at Workspace.SpawnLocation. The hub spawn is the only supported spawn point.
[Ice Melt Incremental] server ready | env=Development (Studio session (default)) | store=IceMelt_PlayerData_DEV_v1 | zones=3 | remotes=ReplicatedStorage.IceMelt.Remotes | world=ok
[Ice Melt Incremental] client ready | env=Development | remotes=ok
```

The first line is an intended one-time warning, not an error.

### Phase 01 evidence

Run 2026-08-02. Play-mode Output, verbatim:

```
[IceMelt] WorldSkeleton: disabled foreign SpawnLocation at Workspace.SpawnLocation. The hub spawn is the only supported spawn point.
[IceMelt] config warning: MonetizationConfig: 11 marketplace ID(s) are still 0 and stay disabled (expected until Phase 09)
[Ice Melt Incremental] server ready | env=Development | store=IceMelt_PlayerData_DEV_v1 | zones=3 | remotes=14 | services=1 [PlayerStateService] | config=0E/1W
[Ice Melt Incremental] client ready | env=Development | remotes=ok | controllers=1 [StateController]
```

| Phase | Command / test | Result |
|---|---|---|
| 01 | `stylua --check`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0. `luau-lsp` first found 4 type errors, all fixed |
| 01 | Remote set matches the schema exactly | **Pass** — 14 created, 14 in schema, 0 unexpected, 0 non-RemoteEvent |
| 01 | Rogue objects planted in the Remotes folder | **Pass** — a backdoor RemoteEvent and a RemoteFunction named `PlayerState` were both destroyed on rebuild; folder returned to 14 and `PlayerState` is a RemoteEvent |
| 01 | No generic client→server command channel | **Pass** — 0 remotes match command/dispatch heuristics; `ConfigAudit` also fails the build if one is added |
| 01 | Client cannot reach an unregistered remote | **Pass** — `fire("AdminCommand")` and `connect("SecretBackdoor")` both rejected |
| 01 | Remote direction enforced both sides | **Pass** — client firing a ServerToClient remote, client listening on a ClientToServer remote, server firing an inbound remote, and server listening on an outbound remote are all rejected |
| 01 | Handshake end to end | **Pass** — `ClientReady` answered with a snapshot containing exactly the 8 `ReplicatedPlayerState` keys. `ReceiptHistory`, `LifetimeHeat`, and `RunHeat` all absent |
| 01 | Deterministic start order | **Pass** — priority order honoured (`Early` before `Late` regardless of registration order); logged once per side |
| 01 | Init-must-not-yield assertion | **Pass** — a service yielding in `Init` was detected and reported |
| 01 | Duplicate service name assertion | **Pass** — rejected |
| 01 | Missing dependency assertion | **Pass** — `expect()` on an unregistered name rejected |
| 01 | `ConfigAudit` over live config | **Pass** — 0 errors, 1 warning (11 marketplace IDs still 0, expected until Phase 09) |
| 01 | `NumberFormatter` | **Pass** — `1,234,567`, `1.23K`, `45.6M`, `999`, `3.5%`, `1h 1m`; NaN renders `--` rather than leaking `nan` |
| 01 | `Validate` rejects hostile payloads | **Pass** — NaN, infinity, fractional levels, oversize arrays, and sparse tables all rejected |

Bug found and fixed during this phase: the handshake was a single fire-and-forget
`ClientReady`. Because it is an event, firing it before the server connected its listener
would drop it silently and leave the client with no state forever. It now retries a bounded
4 times at 0.75s and warns if it gives up; the server's rate limit was widened to match.

### Phase 02 evidence

Run 2026-08-02 against the real DataStore, with Studio API access enabled.
Backend reported at runtime: `DataStore(IceMelt_PlayerData_DEV_v1) persistent=true
environment=Development`.

| Phase | Command / test | Result |
|---|---|---|
| 02 | `stylua`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0 |
| 02 | New player defaults | **Pass** — SchemaVersion 1, Heat/Embers/Thaws 0, all seven upgrades 0, tool 1/1, Backyard unlocked, City locked, LoadStatus `Loaded` |
| 02 | Mutation survives save → release → load | **Pass** — Heat 12345 round-tripped intact |
| 02 | Mutation survives a full Studio session restart | **Pass** — Heat 777 written in one play session, read back in a later one |
| 02 | Two sessions cannot silently overwrite | **Pass** — with a foreign fresh lock planted, `save` returned false, stored Heat stayed 4242 despite the live profile holding 999999, and the foreign lock was left intact |
| 02 | Stale lock from a crashed server is reclaimable | **Pass** — a lock backdated 3600s was reclaimed and the load succeeded |
| 02 | Profile from a newer build is refused, not downgraded | **Pass** — status `Incompatible`; SchemaVersion 99, Heat 31337, and an unknown `SomeFutureField` all survived untouched, and the lock was never claimed |
| 02 | Invalid fields repaired and logged | **Pass** — 23 repairs from a deliberately corrupt profile: NaN Heat, negative LifetimeHeat, infinite Embers, fractional Thaws, string upgrade level, out-of-range Crit, unknown zone `Atlantis`, unknown discovery, negative discovery count, string ReceiptHistory, EquippedTool above HighestTool. A valid FrozenCoin count was preserved |
| 02 | Full profile never replicates | **Pass** — client snapshot has exactly the 8 allow-listed keys; ReceiptHistory, LifetimeHeat, RunHeat, RewardState, Settings, Discoveries, and SchemaVersion all absent |
| 02 | Dev commands unreachable from a client | **Pass** — ServerStorage shows 0 children client-side; the entry point is a BindableFunction, not a remote |
| 02 | No production store touched in Studio | **Pass** — resolved store was `IceMelt_PlayerData_DEV_v1` throughout |

Three bugs found and fixed during this phase:

1. **`DataService.Init` yielded.** It resolved the storage backend, which probes DataStore.
   The Phase 01 Init-yield detector caught it, and the consequence was real: startup
   continued before the backend existed, so the first player's load ran against a nil
   backend, failed, and kicked them. Backend resolution moved to `Start`.
2. **Studio play sessions locked the developer out of their own profile.** `game.JobId` is
   empty in Studio, and the synthetic id was derived from `os.time()`, so every restart
   looked like a different server holding the lock. Restarting within the 150s lock
   timeout produced a kick. The Studio id is now stable per place, so a restarted session
   reclaims its own lock.
3. **A newer-schema profile would have been silently downgraded.** `migrate` refused to
   downgrade, but `repair` still ran and would have stripped unknown fields, and the next
   save would have written that stripped copy back. The refusal now propagates out of
   `normalise` and aborts the load with status `Incompatible`.

Also fixed: `BindToClose` counted outstanding saves inside its spawn loop, so an
early-finishing release could fire the completion signal before the rest were queued.
Players are counted first now. And a brand-new player no longer logs a spurious "profile
was nil, replaced with defaults" repair, which would bury real corruption in join noise.

### Phase 03 evidence

Run 2026-08-02 in Studio play mode against `DataStore(IceMelt_PlayerData_DEV_v1)`.

| Phase | Command / test | Result |
|---|---|---|
| 03 | `stylua`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0 |
| 03 | Ice field built from configuration | **Pass** — 768 cells (3 zones x 256), pooled at startup |
| 03 | First melt within five seconds | **Pass** — **1.98s**, measured by walking the character from the spawn pad into the field and timing the first destroyed cell, travel included |
| 03 | Heat only changes through server mutations | **Pass** — client Heat exactly equalled the server's granted total. The melt payload contains only a sequence number, so there is no position, zone, target, or amount for a client to forge |
| 03 | Remote spam is rate limited | **Pass** — 200 pulses fired in a tight loop produced 12 accepted, exactly the token bucket capacity |
| 03 | Replayed sequence rejected | **Pass** — reusing an old sequence produced no result |
| 03 | Malformed payloads rejected | **Pass** — non-table, string sequence, NaN, negative, and infinite sequence all ignored |
| 03 | Impossible position rejected | **Pass** — standing outside every zone gave 0 accepted, 14 rejected, all `OutOfRange` |
| 03 | Batch does not become one remote per cell | **Pass** — 54 cells delivered across 4 remotes, max 17 cells in a single remote, average 13.5. One-per-cell would have been 54 |
| 03 | Cells respawn without instance churn | **Pass** — 256 Backyard cell instances before melting, during melting, and after respawn. Alive count fell to 240 and recovered to 256 |
| 03 | Melt guard before profile load | **Pass** — pulses before load rejected as `NoProfile`, so no Heat can be granted that a later load would overwrite |
| 03 | Two-player consistency | **Pass** — Studio multi-client run with 2 players in the shared Backyard field. Both clients rendered both players and the same melted geometry. Heat accrued independently (client overlays read 11 and 52 mid-run; persisted profiles `Player_-1` = 56 and `Player_-2` = 19, with separate save counts). Both clients reported 0 rejections, so concurrent play triggered no false rate-limiting. Both profiles were locked by the same server, as expected for one server holding two players |

Two efficiency problems found and fixed while testing:

1. **The client pulsed ten times a second regardless of position**, including while standing
   in the hub with no ice within fifty studs. Every one of those was bandwidth plus a
   server validation for a guaranteed rejection. The client now checks a cheap rectangle
   test against the zone field bounds plus the maximum possible melt radius before sending.
   This is a bandwidth optimisation, not a security control: the server still validates
   every pulse that arrives, and a modified client that ignores it gains only rejections.
2. **Rejection echoes flooded the Output.** A player standing out of bounds produced one
   warning per pulse. Echoes are now throttled to one per reason per second, and remain
   development-only so a live server never tells a client which check it failed.

### Phase 04 evidence

Run 2026-08-02 in Studio play mode against `DataStore(IceMelt_PlayerData_DEV_v1)`.

| Phase | Command / test | Result |
|---|---|---|
| 04 | `stylua`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0 |
| 04 | First upgrade reachable in 15–30s | **Pass** — 28.2s and 18.1s across two runs with realistic play (walk to the ice, then short hops with a pause in each spot) |
| 04 | Candle reachable in roughly 2–4 minutes | **Not met** — see the balance finding below |
| 04 | Client cannot buy free or negative upgrades | **Pass** — a forged `{Key="Power", Cost=0}` was charged the real 15 Heat because the server ignores client-supplied cost entirely. `Cost=-99999`, `Level=100`, and `Levels=50` were all ignored the same way. Unknown key, numeric key, 500-character key, a bare string, and nil were each rejected as `InvalidPayload` or `UnknownUpgrade` |
| 04 | Client cannot equip locked tools | **Pass** — equipping index 8 and index 2 while owning only 1 gave `NotUnlocked`; index 0, -1, 2.5, NaN, and a string gave `InvalidPayload`. A forged `UnlockTool {Index=8, Cost=0}` was ignored and treated as "buy the next tool", failing on price. HighestTool and EquippedTool both remained 1 |
| 04 | Tool changes visibly alter melt behaviour | **Pass** — unlocking Candle through the real remote charged exactly 350, moved HighestTool and EquippedTool to 2, raised Damage 10 → 13.5 (ratio 1.35, exactly Candle's Power multiplier) and Radius 4.5 → 4.75 (+0.25, exactly Candle's bonus), and swapped the held model to the Candle silhouette with its glow and light |
| 04 | Costs and effects come from shared configuration | **Pass** — the charged 350 and the 1.35 damage ratio match `ContentConfig` exactly; the HUD reads costs from `StatMath.upgradeCost`, never a literal |

Bug found and fixed during this phase: **Power was applied per pulse rather than per second.**
`docs/03` specifies Melt Power as "10 damage/sec", but MeltService applied that figure on every
pulse, which at ten pulses a second made it ten times stronger than specified. Backyard cells
died to a single pulse, so buying Power changed nothing in the zone every new player starts in.
It was also an exploit surface: a client pulsing at 12/s instead of 10/s dealt 20% more damage.
Damage is now scaled by elapsed time since the player's last accepted pulse, clamped, so the
melt rate is independent of pulse frequency.

Also fixed: the development overlay was drawn on top of the HUD's Heat panel, making both
unreadable.

### Balance finding: the two pacing targets are in tension

Measured Heat rate for a new player with realistic play: **0.58 Heat/sec**. That puts the
first upgrade at 18–28s, inside the 15–30s target, and Candle at roughly **10 minutes**
against a 2–4 minute target.

The gap is structural rather than a tuning slip:

- The first upgrade costs 15 Heat and Candle costs 350, a 23× gap, while the time targets
  (15–30s versus 120–240s) are only about 8× apart. The Heat rate therefore has to roughly
  triple within the first few minutes.
- The upgrades that raise the Heat rate cannot deliver that in the window. Buying Value to
  level 8 costs about 804 Heat and Radius to level 5 about 866, both more than the 350 being
  saved for, and their per-level effects (×1.12 and +0.45 studs) are too small to compound
  quickly at these prices.
- Movement matters more than expected: at base walk speed 16 and radius 4.5, a cell is inside
  the radius for about 0.56s and needs 1.0s of contact to break, so a single pass never
  destroys a cell. Damage does persist, so cells break on a later pass, but continuous
  sprinting melts almost nothing (measured 0.03 Heat/sec) and standing still is also poor
  (0.16 Heat/sec) because a cleared radius then waits out the 5s respawn.

Efficient play has more headroom than the scripted player achieved: with a 5s respawn and
roughly two cells in radius, the ceiling is near 2 Heat/sec, which would put Candle around
3 minutes. Confirming that needs a human playtest rather than a scripted one; a bot is a poor
proxy for how efficiently a real player sweeps ice.

Deliberately **not** auto-tuned. `docs/03` says not to tune from formulas alone and to record
real playtest timestamps, and the levers that would close the gap (Candle's 350 cost,
Backyard's Heat value of 1, the upgrade cost curves) are all specified values that should not
be changed on simulated data. Owner decision, with three options:

1. Lower early tool costs so the ladder matches the documented minutes.
2. Raise Backyard Heat per cell, and raise the first upgrade's cost to keep the 15–30s beat.
3. Make the first few Value and Radius levels cheaper or stronger so the rate compounds sooner.

Pitch was tuned during this phase and is the one lever that is a local choice rather than a
documented value. Measured across four pitches with realistic play: 6 studs gave 0.58 Heat/sec
(first upgrade 18–28s, in window), 8 studs gave 0.34 (~43s), 9 studs gave 0.13 (~110s). Kept
at 6.

### Phase 05 evidence

Run 2026-08-02 in Studio play mode against `DataStore(IceMelt_PlayerData_DEV_v1)`.

| Phase | Command / test | Result |
|---|---|---|
| 05 | `stylua`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0 |
| 05 | Three zones visually distinct | **Pass** — Backyard is white snow with wooden fence posts, sheds, and toys; Cavern is blue ice with crystal spikes, stalagmites, and neon glow shards under dark blue fog; City is grey concrete with cars, lamp posts, and a tower skyline. Screenshots captured for each |
| 05 | Per-zone lighting applied client-side | **Pass** — on arriving in the Cavern the client reported Brightness 1.2, FogEnd 320, Ambient RGB(48,62,92), matching `ZoneStyleConfig` exactly |
| 05 | Locked travel cannot be forced by client remotes | **Pass** — `TravelZone` to Cavern and City both denied `ZoneLocked`; `UnlockZone` for City while the Cavern was locked denied `PreviousZoneLocked`; unknown zone denied `UnknownZone`; numeric, string, nil, and empty payloads denied `InvalidPayload`. Player stayed in Backyard with nothing unlocked |
| 05 | Locked travel cannot be forced by teleporting | **Pass** — the character was moved straight into the locked Cavern, bypassing every remote. Melting there gave 0 accepted, 4 rejected `WrongZone`, 0 Heat. The patrol then returned the player to the Backyard arrival point with Heat unchanged and the Cavern still locked |
| 05 | Legitimate unlock and travel | **Pass** — charged exactly 25,000 (the configured Cavern cost), moved the player there, and recomputed zone-dependent stats: Luck 1.0 → 1.5 → 1.0 → 1.5 across repeated switches |
| 05 | Zone switching leaks nothing | **Pass** — world instance counts identical before and after repeated switching (998 descendants; 256 cells per zone; 46/70/60 props). Client effect pool stayed at exactly 48, and exactly one HUD and one overlay existed |
| 05 | Zone-specific ice configuration | **Pass** — Cavern yielded about 42 Heat per cell against the Backyard's ~1, from the per-zone Heat and durability values |
| 05 | Cavern unlock in 8–12 minutes | **Not met** — see below |
| 05 | Largest zone multiplayer performance | **Not run** — needs a multi-client session |

Fixed during this phase: the development overlay still overlapped the HUD. The two use
different coordinate origins because the overlay sets `IgnoreGuiInset` and the HUD does not,
so an offset that looks clear in one is overlapping in the other. It now sits bottom-left,
the one corner the HUD does not use. The hub title sign was also 36 studs wide at 12 studs
from the arrival pad and filled the entire view; it is now 26 wide at 22 studs, reading as a
gateway banner over the route to the ice.

### Balance finding, continued: income does not compound

Phase 04 recorded that Candle takes ~10 minutes against a 2–4 minute target. The Cavern at
25,000 Heat is the same problem an order of magnitude larger: at the measured base rate of
0.58 Heat/sec that is roughly 12 hours, against an 8–12 minute target.

Measuring further is not the useful step, because the cause is arithmetic and can be checked
without playing. In `docs/03`, every upgrade's cost grows faster than its effect:

| Upgrade | Cost growth | Effect growth |
|---|---:|---:|
| Power | ×1.32 | ×1.16 |
| Heat Value | ×1.38 | ×1.12 |
| Discovery Luck | ×1.75 | ×1.08 |
| Radius | ×1.55 | +0.45 studs (linear) |
| Crit | ×1.65 | +0.5% (linear) |
| Auto-Melt | ×1.80 | +0.10/sec (linear) |

Each successive level therefore has a longer payback period than the one before, so income
decelerates rather than compounding. An incremental game needs the opposite: progression that
accelerates as the player invests.

Zones do not close the gap either. Income is roughly `damage / durability × HeatPerCell`, and
the Heat-per-durability ratio barely moves between zones — 0.10 in the Backyard, 0.12 in the
Cavern, 0.15 in the City. Measured at identical stats the Cavern was about 2.7× the Backyard's
rate, which does not approach the 43× cost step from Candle to Cavern.

This is one decision, not three, and it is the owner's: the cost curves, the zone values, and
the tool and zone prices are all specified in `docs/03`, and that file explicitly says to tune
from real playtests rather than formulas. The concrete options remain as recorded under Phase
04, with one addition now that the pattern is clear:

4. Make effect growth exceed cost growth on at least one track, so there is a compounding
   route. Value at ×1.12 effect against ×1.38 cost is the clearest candidate to revisit.

### Phase 06 evidence

Run 2026-08-02 in Studio play mode against `DataStore(IceMelt_PlayerData_DEV_v1)`.

| Phase | Command / test | Result |
|---|---|---|
| 06 | `stylua`, `selene`, `rojo build`, `luau-lsp analyze` | **Pass**, all exit 0 |
| 06 | Award and multiplier match `docs/03` | **Pass** — 10,000,000 run Heat previewed 3 Embers (`floor(10^0.55)`), projected multiplier 1.30635 (`1 + 3^0.65 × 0.15`) |
| 06 | Replayed confirmation cannot duplicate Embers | **Pass** — one `ConfirmThaw:Ok`, four replays of the same token denied `NoPendingThaw`. Embers went 0 → 3, not 0 → 15. The log contains exactly one `ThawCompleted` |
| 06 | Fabricated and malformed confirmations | **Pass** — invented token denied `StaleToken`; numeric, empty, string, and nil payloads denied `InvalidPayload` |
| 06 | Token invalidated by a rejoin | **Pass** — a token issued before a save/release/load round trip was denied `NoPendingThaw` afterwards, with no Embers granted and no Thaw counted |
| 06 | Reset fields match documentation | **Pass** — Heat 0, RunHeat 0, all seven upgrades 0, tools back to 1/1, zones back to Backyard only |
| 06 | Retained fields match documentation | **Pass** — Embers 3, Thaws 1, LifetimeHeat 10,000,000, SchemaVersion 1, all surviving a rejoin |
| 06 | Player is moved out of a now-locked zone | **Pass** — thawing while standing in the Cavern returned the player to the Backyard, so the ZoneService patrol never had to treat them as trespassing |
| 06 | Second run is noticeably faster | **Pass** — measured Heat per cell after the Thaw was 1.3063515, exactly the Ember multiplier, against 1.0 before |
| 06 | Thaw analytics logged | **Pass** — `ThawScreenOpened`, `ThawCompleted` (with thaw number, award, Heat banked, total Embers), and `FirstThawCompleted` |
| 06 | First Thaw in roughly 20–30 minutes | **Not met** — see below |

Design notes worth carrying forward:

- The confirmation token is an **intent nonce, not a promise**. The award is always
  recomputed at confirmation from live state, so a stale token cannot lock in a payout from
  a richer moment, and eligibility is re-checked rather than trusted from the preview.
- The token is spent **before** any state changes, so a confirmation arriving twice in the
  same frame finds nothing pending the second time.
- `applyThawReset` writes each field explicitly instead of clearing and rebuilding, so a
  profile field added in a later phase is retained by default. Silently wiping something new
  because a reset function was too clever is how prestige systems destroy progress.
- A permanent Ember node set was **not** built. `docs/03` lists "permanent Ember nodes" among
  retained fields but never specifies any, and the phase says to add them "if documented".
  Inventing a progression system that no document describes would be scope invention.

### Balance finding, third data point

The first Thaw needs 1,000,000 run Heat. At the measured rate of roughly 0.58 Heat/sec that is
about 20 days, against a 20–30 minute target.

This is the same single root cause recorded under Phases 04 and 05, now visible at three
scales: Candle at 350 (~10 min vs 2–4), Cavern at 25,000 (~12 hours vs 8–12 min), and the
first Thaw at 1,000,000 (~20 days vs 20–30 min). The mechanism is unchanged — every upgrade in
`docs/03` has cost growth exceeding effect growth, so income decelerates instead of compounding.

The Ember multiplier does not rescue it: at 3 Embers it is 1.31×, and being sub-linear
(exponent 0.65) it is deliberately modest. It is designed to reward a completed Thaw, not to
be the mechanism that makes the first one reachable.

## Acceptance criteria — Phase 00

| Criterion | Status |
|---|---|
| Rojo changes appear in Studio | **Met** — all three trees synced and verified through MCP |
| Claude can inspect the open DataModel through MCP | **Met** |
| Play mode starts with no red errors | **Met** |
| Environment mode is explicit; production cannot be selected accidentally in Studio | **Met** — resolution is centralised in `EnvironmentConfig`; Production is unreachable in Studio for any override, and unregistered places fall back to Test. Two independent guards (module-level and server bootstrap) |
| `PROJECT_STATUS.md` records evidence and setup blockers | **Met** — this file |

## Known blockers

- **Pass and developer product IDs not created.** All IDs in `MonetizationConfig` are `0`.
  Owner action before Phase 09.
- **`PRODUCTION_PLACE_IDS` is empty.** Deliberate. Until the owner decides which PlaceId
  is production, live servers run against the Test data store and warn once at startup.
- **Norton 360 intercepts HTTPS and breaks Rust-based tooling** (selene, rokit, and any
  future wally/lune). Not blocking today — both affected files are committed — but pausing
  Norton's web scanning is required for any future tool install. See
  `docs/12_LOCAL_ENVIRONMENT.md`.
- **Rojo default port 34872 is taken** by another project (`CoalEmpireTycoon`). Ice Melt
  pins 34873. Connecting this place to 34872 would sync the wrong project's source.
- Final game name and branding are provisional. The published place is
  `IceMeltIncremental`; `GameConfig.GameName` is "Ice Melt Incremental".
- Approved audio and thumbnail assets are not yet uploaded.
- Placeholder world only. The default Baseplate is still present under the Backyard slab;
  Phase 05 replaces the placeholder ground with real zone art.

## Acceptance criteria — Phase 01

| Criterion | Status |
|---|---|
| All Luau files strict and typecheck as far as tooling permits | **Met** — `--!strict` throughout, `luau-lsp analyze` exit 0 |
| Server creates only expected remotes | **Met** — verified by count, name, and class, including a rogue-object rebuild test |
| Client cannot invoke unregistered generic command remotes | **Met** — no such remote exists, `RemoteAccess` rejects unknown names, and `ConfigAudit` blocks one being added |
| Start order logged once in development, no untimed race waits | **Met** — one line per side; every `WaitForChild` has a timeout; `Init` yielding is detected rather than tolerated |
| Build/play test has no red errors | **Met** |

## Acceptance criteria — Phase 02

| Criterion | Status |
|---|---|
| New player gets correct defaults | **Met** |
| Leave/rejoin preserves a test mutation | **Met** — verified both by save/release/load round trip and across a full Studio session restart |
| Two sessions cannot silently overwrite the same profile | **Met** — the losing save writes nothing and says so |
| Invalid fields are repaired and logged | **Met** — 23 distinct repairs exercised |
| Full profile and receipt history never replicate to clients | **Met** — allow-listed snapshot, verified on the wire |
| No production store is touched in Studio | **Met** |

## Acceptance criteria — Phase 03

| Criterion | Status |
|---|---|
| First melt occurs within five seconds | **Met** — 1.98s measured from spawn |
| Heat only changes through server mutations | **Met** |
| Remote spam and impossible position requests rejected/rate-limited | **Met** |
| A batch/chain does not generate one remote per cell | **Met** — 54 cells in 4 remotes |
| Cells respawn without sustained create/destroy churn | **Met** — instance count constant |
| Two-player test shows consistent authoritative results | **Met** |

## Known limitation: concurrent Studio sessions share a lock identity

The Studio session-lock id is stable per place (`studio-<PlaceId>`), which is what lets a
restarted play session reclaim its own lock instead of locking the developer out. The
trade-off is that two Studio sessions running against the same place at the same time —
for example a multi-client test plus a separate play session — share one identity and will
each believe they own the profile locks.

Not a live-server concern, since real servers use their own `game.JobId`. In Studio, avoid
running a second play session while a multi-client test is open.

## Acceptance criteria — Phase 04

| Criterion | Status |
|---|---|
| First upgrade reachable in 15–30 seconds | **Met** — 18.1s and 28.2s measured |
| Candle reachable in roughly 2–4 minutes | **Not met** — ~10 min measured. See the balance finding above; needs an owner tuning decision plus a human playtest |
| Client cannot buy free/negative upgrades or equip locked tools | **Met** |
| Tool changes visibly alter melt behaviour | **Met** |
| Costs and effects come from shared configuration | **Met** |

## Acceptance criteria — Phase 05

| Criterion | Status |
|---|---|
| All three zones visually distinct and traversable | **Met** |
| Cavern unlock playtest target of 8–12 minutes | **Not met** — ~12 hours at the measured base rate. Same root cause as the Phase 04 gap |
| Locked travel cannot be forced by remotes or by teleporting | **Met** — two independent guards, both verified |
| Zone switching does not leak fields/effects or multiply loops | **Met** |
| Largest zone performance in a multiplayer test | **Not run** |

## Acceptance criteria — Phase 06

| Criterion | Status |
|---|---|
| First Thaw reachable in roughly 20–30 minutes | **Not met** — ~20 days at the measured rate. Same single root cause as Phases 04 and 05 |
| Replayed/stale confirmation cannot duplicate Embers | **Met** — verified against replay, fabrication, malformed payloads, and a rejoin |
| Reset and retained fields exactly match documentation | **Met** |
| Player resumes a noticeably faster second run | **Met** — Heat per cell 1.0 → 1.3063515, exactly the Ember multiplier |

## Next action

**The economy question is now the only thing worth doing next.** Every mechanic through Phase
06 is built, secure, and verified; three separate pacing targets miss by two to four orders of
magnitude for one shared reason. Phase 07 (discoveries and their rarity weighting) would be
the fourth system tuned against a curve that does not compound.

1. **Decide the economy question.** Options are recorded under the Phase 04 and 05 findings.
   The clearest single change is making effect growth exceed cost growth on at least one
   track, so a compounding route exists at all.
2. **Play for five minutes and record real timings.** Every pacing number so far comes from a
   scripted player, which is a poor proxy for how efficiently a human sweeps ice.
3. **Run a two-player session in the Frozen City** to close the outstanding Phase 05
   performance criterion.

Then run Phase 07 — frozen discoveries, rarity, collection index, and chain reactions.

Phase 07 must preserve: the `EnvironmentConfig` production guard, the closed remote schema,
one development-only startup line per bootstrap, `Init` never yielding, and gameplay gated on
`DataService.isLoaded(player)`.

`ContentConfig.Discoveries` already holds all twenty with zone and rarity, and
`BalanceConfig.Discovery` holds the rarity weights and `MinCommonWeight`.
`PlayerStateService.addDiscovery` already validates the key against the catalogue and returns
whether it was the player's first of that kind, which is what the reveal card needs.
`StatMath.computeMeltStats` returns a zone-adjusted `Luck` for weighting the roll. Chain
reactions must award through the same validated path as a normal melt, with the per-event cap
from `ContentConfig.Chains`.
