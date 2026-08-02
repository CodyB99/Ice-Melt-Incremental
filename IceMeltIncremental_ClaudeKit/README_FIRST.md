# Ice Melt Incremental — Claude Code Project Kit

This repository kit is the operating manual for building the first commercial MVP of **Ice Melt Incremental** in Roblox.

## Start here

1. Install or update Roblox Studio, Git, Claude Code, and Rokit.
2. Open Roblox Studio and create a blank Baseplate experience owned by the Roblox group/account that will publish the game.
3. In Studio, open **Assistant Settings → MCP Servers → Quick connect** and enable **Claude Code**.
4. Install the Rojo Studio plugin, then open a terminal in this folder.
5. Run `rokit install` to install the pinned toolchain (rojo, stylua, selene, luau-lsp).
6. Run `rojo serve`, then set the Rojo plugin's port to **34873** and connect. Confirm the plugin reports `IceMeltIncremental`.
7. Start Claude Code with `claude` from this repository root.
8. Tell Claude: `Read CLAUDE.md and PROJECT_STATUS.md. Then run Phase 00 exactly as written.`
9. After each phase, use `/review-current-phase 00`, replacing `00` with the phase number.
10. Do not skip a phase because the later prompts assume the earlier acceptance tests passed.

> **Port 34873, not the Rojo default 34872.** Another project on this machine holds 34872.
> Connecting this place to 34872 syncs the wrong project's source into it.

## Most useful commands

- `/build-next-phase 00` — execute a phase prompt.
- `/review-current-phase 00` — audit the phase against its acceptance criteria.
- `/studio-mcp-test` — inspect and play-test the open Studio experience through MCP.
- `rokit install` — install the pinned toolchain.
- `rojo serve` — live-sync Luau source files to Studio on port 34873.
- `.\scripts\analyze.ps1` — strict Luau typecheck; the authoritative static check.
- `.\scripts\format.ps1` — apply stylua formatting.
- `rojo build default.project.json -o IceMeltIncremental.rbxlx` — produce a local place build.

See `docs/12_LOCAL_ENVIRONMENT.md` for every command and the known tool limitations.

## Critical owner tasks Claude cannot complete by itself

- ~~Create and publish the Roblox experience under the correct owner/group.~~ Done 2026-08-02: PlaceId `87210191828303`, universe `10620948462`, registered in `EnvironmentConfig` as **Test**.
- Decide which PlaceId is production, then move it into `PRODUCTION_PLACE_IDS`. Until then no server can reach the production data store.
- Create passes and developer products in Creator Dashboard.
- Paste the real asset/product/pass IDs into `src/shared/Config/MonetizationConfig.luau`.
- Upload approved icons, thumbnails, audio, and any custom meshes.
- Review every Toolbox/Creator Store asset for hidden scripts and licensing.
- Perform final device testing and publish the production version.

## MVP definition

A release candidate is complete when a new player can:

1. Melt ice within five seconds of spawning.
2. Earn Heat and purchase upgrades.
3. unlock eight heat tools and three zones.
4. find frozen discoveries with rarity feedback.
5. perform a Thaw reset for permanent Embers.
6. leave and rejoin without losing progress.
7. purchase test passes/products safely with idempotent receipt handling.
8. complete onboarding on mobile, controller, and keyboard/mouse.

Do not add pets, trading, clans, PvP, crafting, multiple prestige layers, or a second place before the MVP is proven.
