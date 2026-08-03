# Project Status

Updated: 2026-08-02

## Phase checklist

- [x] 00 — Repository, Rojo, Studio MCP, and DataModel setup
- [x] 01 — Shared types, configuration, remotes, and bootstrapping
- [x] 02 — Player data, session safety, and replicated state
- [x] 03 — Ice fields, server-authoritative melt loop, and pooling
- [ ] 04 — Heat economy, upgrades, tool progression, and number formatting
- [ ] 05 — Three zones, gates, world construction, and travel
- [ ] 06 — Thaw prestige and permanent Ember progression
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

## Next action

Run Phase 04 — Heat economy, upgrades, tool progression, and number formatting.

Phase 04 must preserve: the `EnvironmentConfig` production guard, the closed remote schema,
one development-only startup line per bootstrap, `Init` never yielding, and gameplay gated
on `DataService.isLoaded(player)`.

`StatMath.upgradeCost` already implements the documented cost curve and returns nil at the
cap; use it rather than recomputing. Spend Heat only through `PlayerStateService.addHeat`
with a negative amount, and apply levels only through `setUpgradeLevel`, which validates
against the configured cap. Both already replicate and mark the profile dirty.
