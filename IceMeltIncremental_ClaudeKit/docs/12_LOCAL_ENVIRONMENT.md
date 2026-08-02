# Local Environment and Commands

Recorded in Phase 00. Update this file whenever a command or tool version changes.

## Toolchain

Managed by [Rokit](https://github.com/rojo-rbx/rokit) and pinned in `rokit.toml`:

| Tool | Version | Purpose |
|---|---|---|
| rojo | 7.5.1 | Sync source to Studio, build place files, generate sourcemaps |
| stylua | 2.0.2 | Formatting (`stylua.toml`, CRLF, tabs, 100 columns) |
| selene | 0.27.1 | Lua lint (see limitation below) |
| luau-lsp | 1.69.0 | Strict Luau typecheck |

Install from this directory:

```
rokit install
```

The Rojo CLI version must stay protocol-compatible with the Rojo Studio plugin (currently
7.5.1). Upgrade both together.

## Commands

Run from `IceMeltIncremental_ClaudeKit/`.

| Command | What it does |
|---|---|
| `rojo serve` | Live-sync source to Studio on **port 34873** |
| `rojo build default.project.json -o IceMeltIncremental.rbxlx` | Build a local place file |
| `.\scripts\start-dev.ps1` | `rojo serve` with a reminder about the port |
| `.\scripts\build.ps1` | Build the place file |
| `.\scripts\format.ps1` | Apply stylua to `src` |
| `.\scripts\analyze.ps1` | Sourcemap + strict Luau typecheck (**the authoritative static check**) |
| `.\scripts\fetch-types.ps1` | Download Roblox type definitions into `tools/` (gitignored) |
| `.\scripts\lint.ps1` | selene lint, offline via the committed `roblox.yml` |

## Rojo port is 34873, not 34872

Another project on this machine (`CoalEmpireTycoon`) permanently holds the Rojo default
port 34872. Ice Melt therefore pins `"servePort": 34873` in `default.project.json`.

In the Rojo Studio plugin: **Settings → Port → 34873**, then Connect.

> Connecting this place to port 34872 syncs a different project's source into it. Always
> confirm the plugin reports `IceMeltIncremental` after connecting.

## Line endings

`.gitattributes` declares `* text=auto eol=crlf`: Git stores LF in the repository and
checks out CRLF in the working tree. This matches `stylua.toml`
(`line_endings = "Windows"`) and PowerShell.

Without that file, `core.autocrlf=true` guessed per file, so `.luau` sources were CRLF
while every `.md`/`.json`/`.toml`/`.ps1` file was LF, and the editor warned on each open.

## Norton intercepts HTTPS, which breaks Rust-based tools

**This will bite again.** Norton 360 terminates every HTTPS connection and re-signs it
with a `Norton Web/Mail Shield Root` certificate, which it installs into the Windows
certificate store.

- Anything using the Windows store works: PowerShell, .NET, browsers, Roblox Studio.
- Anything shipping its own root list fails with `invalid peer certificate: UnknownIssuer`.
  That includes **selene**, **rokit**, and most other Rust tooling (wally, lune, …).

Setting `SSL_CERT_FILE` to Norton's exported root does **not** help; these binaries use
rustls with bundled roots and ignore it.

Symptoms seen in Phase 00:

```
rokit add rojo-rbx/rojo    -> GitHub error: reqwest middleware error: Request failed after 3 retries
selene generate-roblox-std -> tls connection init failed: invalid peer certificate: UnknownIssuer
```

**Workaround:** pause Norton's web/HTTPS scanning, run the one command that needs the
network, then re-enable it. Both known cases are one-time:

- `rokit.toml` was written by hand against tools already in Rokit's local storage.
- `roblox.yml` is generated once and committed (below).

If you add more Rust tooling later, consider excluding `C:\Users\<you>\.rokit\` from
Norton's encrypted-traffic scanning rather than pausing protection each time.

### selene's Roblox standard library is committed

`selene.toml` sets `std = "roblox"`. selene normally downloads the live Roblox API dump to
build that standard library, which Norton blocks. The generated `roblox.yml` is therefore
**committed to the repository**, so `selene src` runs completely offline on any machine.

Regenerate only when the Roblox API changes materially:

```
selene generate-roblox-std
```

Note the command may print an API-dump error and exit non-zero even when it has written a
complete `roblox.yml`. Check the file's header timestamp and run `selene src` to confirm
before trusting the exit code.

### Roblox type definitions are a download, not a checked-in file

`scripts/analyze.ps1` needs `tools/globalTypes.d.luau`. It is gitignored and fetched by
`scripts/fetch-types.ps1` from the official luau-lsp repository. A fresh clone must run
that once before analysing.

## Studio MCP

Available and used in Phase 00 for: DataModel inspection, Edit/Server Luau execution,
console reads, play start/stop, and screen capture. Studio must be open with the place
loaded and the MCP server enabled under Assistant Settings.
