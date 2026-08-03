--!strict

--[[
	MeltService

	Server-authoritative melt loop. Implements the melt protocol in docs/02.

	The client sends a sequence number and nothing else that matters. Everything used to
	decide the outcome is read on the server:

	    profile loaded      -- a reward granted before the profile loads gets overwritten
	    character alive     -- position comes from the HumanoidRootPart, never the client
	    sequence is newer   -- replaying an old pulse must do nothing
	    token bucket        -- a burst is fine, a sustained flood is not
	    zone from position  -- the player is in the zone the server puts them in
	    radius from stats   -- derived from the authoritative profile and tool
	    cells from the grid -- only cells actually inside that radius
	    caps                -- on cells per pulse and Heat per pulse

	The client's requested cell list is deliberately ignored. Accepting it would mean
	trusting a client to name its own targets, and validating a supplied list costs more
	than simply computing the correct one.

	Results are returned as a single batched MeltResult per pulse. One remote per cell is
	explicitly forbidden by docs/02, and a chain reaction would make it catastrophic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local DiscoveryService = require(script.Parent:WaitForChild("DiscoveryService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local IceFieldService = require(script.Parent:WaitForChild("IceFieldService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))

type MeltRejectReason = Types.MeltRejectReason

local MeltService = {
	Name = "MeltService",
	Priority = 30,
}

-- Zone membership is defined once, in ZoneService. Keeping a second copy here would let the
-- two drift, and a player could then be in-zone for melting but out-of-zone for enforcement.
local ZoneService = require(script.Parent:WaitForChild("ZoneService", 10))

local buckets: { [Player]: Validate.TokenBucket } = {}
local lastSequence: { [Player]: number } = {}
local lastPulseAt: { [Player]: number } = {}

-- Fractional Auto-Melt pulses carried between sweeps. See runAutoPulses.
local autoCredit: { [Player]: number } = {}

--[[
	Damage is per second, not per pulse.

	docs/03 specifies Melt Power as "10 damage/sec". Applying that figure once per pulse
	made it ten times stronger than specified, which broke the balance curve outright:
	Backyard cells died to a single pulse, so buying Power changed nothing in the zone every
	new player starts in.

	Scaling by elapsed time also removes pulse rate as an exploit axis. A client that pulses
	faster now covers the same ground in the same time rather than dealing proportionally
	more damage, so the rate limiter protects bandwidth rather than being the only thing
	standing between a fast client and free progress.

	The delta is clamped: without a ceiling, a player who stops pulsing and resumes would
	land one enormous accumulated hit.
]]
local NOMINAL_PULSE_INTERVAL = 1 / GameConfig.Limits.MaxMeltPulsesPerSecond
local MAX_PULSE_DELTA = NOMINAL_PULSE_INTERVAL * 3

--[[
	Auto-Melt.

	docs/03 specifies the track in pulses per second, so that is what this delivers:
	`AutoRate` extra melt pulses a second, each worth one nominal pulse of damage, driven
	entirely by the server.

	One sweep for every player rather than a timer each, matching how IceFieldService handles
	respawns. The sweep runs faster than the highest reachable rate so a fractional rate is
	averaged rather than rounded away.
]]
local AUTO_SWEEP_INTERVAL = 0.25

-- Safety ceiling per sweep. AutoRate maxes at 2.0/sec from the documented curve, so this is
-- never reached in normal play; it exists so a long frame or a future config change cannot
-- turn accumulated credit into one enormous burst.
local MAX_AUTO_PULSES_PER_SWEEP = 8

-- Diagnostics for the development overlay. Server-side counters only.
local stats = {
	-- A pulse that passed validation AND found ice to damage.
	Accepted = 0,
	-- A pulse that passed validation but had nothing in range. Counted apart from Accepted
	-- so the accepted figure keeps meaning "did work"; lumping the two together made an idle
	-- player standing on cleared ice look like a busy one.
	Idle = 0,
	Rejected = 0,
	AutoPulses = 0,
	CellsDestroyed = 0,
	HeatGranted = 0,
	RejectionsByReason = {} :: { [string]: number },
}

-- Last time each player was told about each rejection reason, so a persistent condition
-- reports once a second instead of ten times.
local lastEchoAt: { [Player]: { [string]: number } } = {}
local ECHO_INTERVAL = 1

local function reject(player: Player, reason: MeltRejectReason)
	stats.Rejected += 1
	stats.RejectionsByReason[reason] = (stats.RejectionsByReason[reason] or 0) + 1

	-- Rejection reasons are only echoed in development. On a live server telling a client
	-- exactly which check it failed just helps someone tune an exploit.
	if not GameConfig.Debug.ShowMeltDiagnostics then
		return
	end

	-- Throttled per reason. A player standing outside a zone rejects on every pulse, and
	-- an unthrottled echo buries every other message in the output.
	local perPlayer = lastEchoAt[player]
	if not perPlayer then
		perPlayer = {}
		lastEchoAt[player] = perPlayer
	end

	local now = os.clock()
	if perPlayer[reason] and now - perPlayer[reason] < ECHO_INTERVAL then
		return
	end
	perPlayer[reason] = now

	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = "MeltPulse",
		Status = "Denied",
		Reason = reason,
	})
end

--[[
	Applies one melt event: damages every eligible cell, grants the Heat for whatever was
	destroyed, and returns the batch the client needs for effects.

	Shared by the player's own pulses and by Auto-Melt, so both go through the same cell
	query, the same cap, the same one-credit-per-cell rule, and the same reward ceiling. A
	separate implementation for Auto-Melt would be a second place to forget a clamp.

	Callers own validation and the damage figure; this function assumes both are settled.
]]
local function applyMelt(
	player: Player,
	zoneKey: string,
	meltStats: Types.DerivedStats,
	position: Vector3,
	damagePerCell: number
): ({ Types.MeltCellResult }, number, number)
	local cells = IceFieldService.queryCells(
		zoneKey,
		position,
		meltStats.Radius,
		GameConfig.Limits.MaxCellsPerPulse
	)

	local results: { Types.MeltCellResult } = {}
	local totalHeat = 0
	local destroyed = 0

	for _, cell in cells do
		-- Crits multiply the reward, not the damage. Scaling damage as well would make
		-- Crit a second Power stat and double-dip against the balance curve.
		local critical = math.random() < meltStats.CritChance
		local wasDestroyed = IceFieldService.damageCell(cell, damagePerCell)

		if wasDestroyed then
			destroyed += 1
			totalHeat += StatMath.heatForCell(meltStats, zoneKey, critical)
		end

		table.insert(results, {
			CellId = cell.Id,
			Damage = damagePerCell,
			Destroyed = wasDestroyed,
			Critical = critical and wasDestroyed,
		})
	end

	-- Final ceiling on the reward, after every multiplier.
	totalHeat = Validate.clampFinite(totalHeat, 0, BalanceConfig.Melt.MaxHeatPerPulse)

	if totalHeat > 0 then
		--[[
			Routed through EconomyService rather than straight to addHeat, so melt income
			appears in the ledger alongside every other source and sink.

			Behaviourally identical — grant re-checks isLoaded and a positive amount, both
			already true here, then calls the same addHeat — but the ledger was previously
			recording zone unlocks, tool unlocks and upgrade purchases while showing no melt
			income at all. Phase 07 adds DiscoveryReward and ChainReaction to it, and a ledger
			that showed those without the melt that produced them would be actively misleading.
		]]
		EconomyService.grant(player, totalHeat, "IceMelt")
	end

	return results, totalHeat, destroyed
end

local function onMeltPulse(player: Player, payload: any)
	-- Type validation before anything else. Everything past here is a number we checked.
	if type(payload) ~= "table" then
		reject(player, "InvalidPayload")
		return
	end

	local sequence = (payload :: any).Sequence
	if not Validate.isIntegerInRange(sequence, 1, 1e12) then
		reject(player, "InvalidPayload")
		return
	end

	-- Replay and reorder protection. Only strictly newer sequences count.
	local previous = lastSequence[player] or 0
	if sequence <= previous then
		reject(player, "StaleSequence")
		return
	end

	if not DataService.isLoaded(player) then
		-- Granting Heat now would be written over when the real profile loads.
		reject(player, "NoProfile")
		return
	end

	local bucket = buckets[player]
	if not bucket or not Validate.consumeToken(bucket, os.clock()) then
		reject(player, "RateLimited")
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		reject(player, "NoCharacter")
		return
	end

	-- Position is read from the server's copy of the character, never from the payload.
	local position = root.Position

	local zoneKey = ZoneService.zoneAt(position)
	if not zoneKey then
		reject(player, "OutOfRange")
		return
	end

	if not PlayerStateService.isZoneUnlocked(player, zoneKey) then
		reject(player, "WrongZone")
		return
	end

	-- Sequence is only committed once the pulse is otherwise valid, so a rejected pulse
	-- cannot burn a sequence number and stall the client.
	lastSequence[player] = sequence

	-- Stats come from the one module that computes them, cached per player and zone.
	-- Recomputing seven upgrade curves on every pulse, twelve times a second per player,
	-- would be pure waste.
	local meltStats = StatsService.get(player, zoneKey)
	if not meltStats then
		reject(player, "NoProfile")
		return
	end

	--[[
		Elapsed time since this player's last accepted pulse, clamped.

		Computed before the cell query and committed unconditionally. Previously the clock
		was only advanced once cells were found, so every pulse that reached no ice left it
		parked; the idle time was then banked and paid out as one oversized hit on the first
		pulse that did reach ice. Walking off the field for a moment and stepping back on
		dealt up to three nominal pulses in one frame.

		The delta is still clamped, so a genuine gap (a respawn, a stall) cannot land one
		enormous accumulated hit either.
	]]
	local now = os.clock()
	local previousPulse = lastPulseAt[player]
	local delta = if previousPulse
		then math.clamp(now - previousPulse, 0, MAX_PULSE_DELTA)
		else NOMINAL_PULSE_INTERVAL
	lastPulseAt[player] = now

	local results, totalHeat, destroyed =
		applyMelt(player, zoneKey, meltStats, position, meltStats.Damage * delta)

	--[[
		Nothing in range is a normal outcome, not an error, and it needs no reply.

		The client uses MeltResult purely for feedback: an empty batch produces no burst, no
		sound and no popup, so answering one was a remote a pulse that told the client
		nothing. A player standing on ice they have already cleared pulses ten times a second
		while it respawns, so this was ten wasted remotes a second each way, per player.

		The clock above is still advanced, which is what stops the idle time being banked and
		paid out as a burst on the next pulse that does reach ice.
	]]
	if #results == 0 then
		stats.Idle += 1
		return
	end

	--[[
		Discovery roll, from the server's own count of cells that made the alive-to-dead
		transition. The award, its Heat, its save and its announcement all happen inside this
		call and are complete before the reply is built, so the reveal the client draws is a
		consequence of an award that already exists rather than a promise of one.

		Wrapped: a fault in the discovery path must not cost the player the melt they earned.
	]]
	local rolled, discovery =
		pcall(DiscoveryService.rollForMeltEvent, player, zoneKey, meltStats, destroyed, 0)
	if not rolled then
		warn(
			string.format("[IceMelt] MeltService: discovery roll errored: %s", tostring(discovery))
		)
		discovery = nil
	end

	local discoveryHeat = if discovery then discovery.HeatAwarded else 0

	stats.Accepted += 1
	stats.CellsDestroyed += destroyed
	stats.HeatGranted += totalHeat + discoveryHeat

	-- One remote for the whole pulse, carrying every cell touched.
	RemoteRegistry.fireClient(RemoteNames.Name.MeltResult, player, {
		Sequence = sequence,
		ZoneKey = zoneKey,
		Cells = results,
		-- The discovery's Heat is folded in because the client shows one popup per batch, not
		-- one per source. The grant itself already happened, inside the roll.
		HeatGranted = totalHeat + discoveryHeat,
		DiscoveryKey = if discovery then discovery.Key else nil,
		DiscoveryIsNew = if discovery then discovery.IsNew else nil,
	})
end

--[[
	Runs whatever Auto-Melt pulses `elapsed` seconds have earned this player.

	Every guard the manual path applies is applied here too — profile loaded, character
	alive, zone derived from the server's own copy of the position, zone unlocked — because
	Auto-Melt melts real cells and grants real Heat. It skips only the two guards that exist
	to police a client: the sequence check and the rate limiter. There is no client here.

	Damage is a fixed nominal pulse rather than the manual path's elapsed-time scaling. The
	manual delta already accounts for every second of wall clock, so scaling auto pulses the
	same way would hand the same second to both paths and pay for it twice.
]]
-- Variadic return type so `local ok, err = pcall(runAutoPulses, ...)` has a second value to
-- bind, the same reason ZoneService.patrol is declared this way. Nothing is ever returned.
local function runAutoPulses(player: Player, elapsed: number): ...any
	if not DataService.isLoaded(player) then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end

	local position = root.Position

	local zoneKey = ZoneService.zoneAt(position)
	if not zoneKey or not PlayerStateService.isZoneUnlocked(player, zoneKey) then
		return
	end

	local meltStats = StatsService.get(player, zoneKey)
	if not meltStats or meltStats.AutoRate <= 0 then
		-- Nobody has bought the track yet, which is the common case. Cheap early exit.
		return
	end

	-- Fractional pulses carry between sweeps, so a rate below the sweep frequency still
	-- fires at the correct average rate instead of being rounded to nothing.
	local credit = (autoCredit[player] or 0) + meltStats.AutoRate * elapsed
	local pulses = math.floor(credit)
	autoCredit[player] = credit - pulses

	if pulses <= 0 then
		return
	end
	pulses = math.min(pulses, MAX_AUTO_PULSES_PER_SWEEP)

	local results, totalHeat, destroyed = applyMelt(
		player,
		zoneKey,
		meltStats,
		position,
		meltStats.Damage * NOMINAL_PULSE_INTERVAL * pulses
	)

	stats.AutoPulses += pulses
	stats.CellsDestroyed += destroyed
	stats.HeatGranted += totalHeat

	if #results == 0 then
		-- No ice in range. Say nothing rather than spending a remote a second telling the
		-- client that nothing happened.
		return
	end

	RemoteRegistry.fireClient(RemoteNames.Name.MeltResult, player, {
		-- Server-originated, so there is no client sequence to echo. The client uses the
		-- batch for effects only and does not sequence-check inbound results.
		Sequence = 0,
		ZoneKey = zoneKey,
		Cells = results,
		HeatGranted = totalHeat,
	})
end

--[[
	Server-side counters, for the development overlay and tests.
]]
function MeltService.getStats()
	return {
		Accepted = stats.Accepted,
		Idle = stats.Idle,
		Rejected = stats.Rejected,
		AutoPulses = stats.AutoPulses,
		CellsDestroyed = stats.CellsDestroyed,
		HeatGranted = stats.HeatGranted,
		RejectionsByReason = table.clone(stats.RejectionsByReason),
		AliveCells = IceFieldService.countAlive(),
		TotalCells = IceFieldService.countTotal(),
	}
end

--[[
	Walk speed is an upgrade, so it is applied from authoritative state every time a
	character spawns. Doing it here rather than trusting a client-side setter means a
	client cannot grant itself speed.
]]
local function applyWalkSpeed(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local waited = character:WaitForChild("Humanoid", 10)
		if not waited or not waited:IsA("Humanoid") then
			return
		end
		humanoid = waited
	end

	local profile = DataService.getProfile(player)
	if profile and humanoid then
		humanoid.WalkSpeed = StatMath.upgradeEffect("Speed", profile.Upgrades.Speed)
	end
end

local function onPlayerAdded(player: Player)
	-- Capacity allows a short burst; refill matches the configured sustained rate.
	buckets[player] = Validate.newTokenBucket(
		GameConfig.Limits.MaxMeltPulsesPerSecond,
		GameConfig.Limits.MaxMeltPulsesPerSecond,
		os.clock()
	)
	lastSequence[player] = 0

	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(applyWalkSpeed, player, character)
	end)

	if player.Character then
		task.spawn(applyWalkSpeed, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	buckets[player] = nil
	lastSequence[player] = nil
	lastEchoAt[player] = nil
	lastPulseAt[player] = nil
	autoCredit[player] = nil
end

function MeltService.Init()
	RemoteRegistry.connect(RemoteNames.Name.MeltPulse, onMeltPulse)
end

function MeltService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		if not buckets[player] then
			onPlayerAdded(player)
		end
	end

	--[[
		Auto-Melt sweep. One loop for every player rather than a timer each, matching how
		IceFieldService batches respawns.

		Wrapped in pcall per player so one player's failure cannot kill the loop and silently
		switch Auto-Melt off for everybody else for the rest of the server's life.
	]]
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(AUTO_SWEEP_INTERVAL)

			local now = os.clock()
			-- Clamped so a hitch or a resumed session cannot mint a burst of credit.
			local elapsed = math.clamp(now - last, 0, AUTO_SWEEP_INTERVAL * 4)
			last = now

			for _, player in Players:GetPlayers() do
				local ok, err = pcall(runAutoPulses, player, elapsed)
				if not ok then
					warn(
						string.format(
							"[IceMelt] MeltService: auto-melt errored for %s: %s",
							player.Name,
							tostring(err)
						)
					)
				end
			end
		end
	end)
end

return MeltService
