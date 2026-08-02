# Project Status

Updated: 2026-08-02

## Phase checklist

- [x] 00 — Repository, Rojo, Studio MCP, and DataModel setup
- [x] 01 — Shared types, configuration, remotes, and bootstrapping
- [ ] 02 — Player data, session safety, and replicated state
- [ ] 03 — Ice fields, server-authoritative melt loop, and pooling
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

## Next action

Run Phase 02 — persistence and player state.

Phase 02 must preserve: the `EnvironmentConfig` production guard, server-created runtime
containers, the closed remote schema, and one development-only startup line per bootstrap.
`PlayerStateService` currently serves in-memory defaults; Phase 02 replaces those with
profiles loaded through `DataService` while keeping the module's public shape
(`getState` returning a copy, and clients never receiving a profile).
