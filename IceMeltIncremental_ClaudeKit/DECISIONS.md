# Architecture and Product Decisions

Record decisions that materially change scope, dependencies, data schema, security, economy, or release behavior.

| Date | Decision | Reason | Consequences |
|---|---|---|---|
| 2026-08-02 | Use a small three-zone MVP | Launch and validate quickly | Later content must remain configuration-driven |
| 2026-08-02 | Use vanilla Roblox APIs for MVP | Reduce dependency and setup risk | Persistence/session safety must be tested carefully |
| 2026-08-02 | Server-authoritative melt rewards | Prevent simple remote exploitation | Client effects may be predicted but reconciled |
| 2026-08-02 | One Thaw prestige layer | Avoid progression bloat before retention data | Additional layers remain post-launch backlog |
| 2026-08-02 | Environment resolved once in `EnvironmentConfig`, never from `RunService:IsStudio()` at call sites | Phase 00 requires the mode to be explicit and production to be unreachable by accident | Production requires an allow-listed PlaceId and is rejected outright in Studio; unregistered places fall back to Test, never Production |
| 2026-08-02 | World skeleton built at runtime by the server, not hand-placed in Studio | Reproducible from source control, cannot drift from configuration, and matches the phase requirement for server-created runtime folders | Edit mode shows a bare place; the world only exists in Play. Builder is idempotent and versioned so layout changes rebuild rather than accumulate |
| 2026-08-02 | Foreign SpawnLocations disabled rather than destroyed at startup | The Baseplate template spawn sits inside the Backyard slab and would break onboarding | Change is reversible and logged; only `Hub/Spawn` is enabled |
| 2026-08-02 | Commit selene's generated `roblox.yml` instead of downloading it per machine | Norton 360's HTTPS interception makes selene's API-dump download fail with `UnknownIssuer`; rustls ignores the Windows certificate store | `selene src` runs offline everywhere. Regenerate only on a material Roblox API change, which needs Norton's web scanning paused once |
| 2026-08-02 | Run both `luau-lsp analyze` and `selene` as required checks | They catch different classes of defect: the typechecker found a union-narrowing bug, selene found duplicate `if`/`else` branches | `scripts/analyze.ps1` and `scripts/lint.ps1` both gate a phase, and both fail hard rather than warn |
| 2026-08-02 | Rojo serves on port 34873 | The default 34872 is permanently held by another project on this machine | Port pinned in `default.project.json`; the Rojo plugin must be set to 34873 or it will sync the wrong project |
| 2026-08-02 | `.gitattributes` pins `* text=auto eol=crlf` | `core.autocrlf` was guessing per file, so `.luau` was CRLF and everything else LF | Repository stores LF, working tree is CRLF, matching `stylua.toml` and PowerShell. All 46 mixed files normalised |
| 2026-08-02 | First published place registered as **Test**, not Production | Publishing must never silently point a live server at production player data | `PRODUCTION_PLACE_IDS` stays empty until the owner explicitly promotes a place |
