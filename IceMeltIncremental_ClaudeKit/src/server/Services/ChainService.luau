--!strict

--[[
	ChainService

	Heat Pocket, Lava Capsule, and Unstable Reactor: the three chain reactions from docs/04.

	A chain object is an existing pooled ice cell flagged as a seed, never a spawned prop.
	Cells are created once at startup and never destroyed, so flagging one costs nothing and
	keeps the "no instance churn" property intact; a prop would also sit off the grid, where
	the field's index arithmetic could not find it.

	Two rules the whole design rests on:

	  * Chains do not cascade. Propagation destroys cells directly and clears any seed it
	    passes over, so one pulse can never trigger a chain that triggers another. This is
	    enforced by never calling back into the trigger path, not by a flag — a module-level
	    "in a chain" flag would leak across players and pulses.
	  * The seed is consumed before anything is awarded. A pulse that destroys several seeds
	    resolves the highest-tier one and consumes the rest without firing them, so there is no
	    pending state for a later pulse to replay.

	The reward goes through `IceFieldService.damageCell`, the same function a normal melt uses,
	which returns true only on the alive-to-dead transition. That is what makes a cell
	creditable exactly once, and it is already covered by the double-credit dev test.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ChainConfig = require(ConfigFolder:WaitForChild("ChainConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService", 10))
local AnnouncementService = require(script.Parent:WaitForChild("AnnouncementService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local IceFieldService = require(script.Parent:WaitForChild("IceFieldService", 10))

local ChainService = {
	Name = "ChainService",
	-- After IceFieldService (20), before DiscoveryService (25) and MeltService (30).
	Priority = 22,
}

export type ChainOutcome = {
	ChainKey: string,
	OriginCellId: number,
	Credited: number,
	HeatAwarded: number,
	Cells: { Types.MeltCellResult },
}

-- Module-local generator. Never seeded from anything world- or client-derived: reproducible
-- chain locations would be an exploit, unlike the deliberately seeded prop layout.
local rng = Random.new()

local definitionByKey: { [string]: Types.ChainDefinition } = {}
local tierRank: { [string]: number } = {}
for index, definition in ContentConfig.Chains do
	definitionByKey[definition.Key] = definition
	tierRank[definition.Key] = index
end

local stats = {
	Armed = 0,
	Fired = 0,
	CellsDestroyed = 0,
	HeatGranted = 0,
	SeedsConsumedWithoutFiring = 0,
	ByChain = {} :: { [string]: number },
}

--[[
	Effective cell ceiling for a chain: the configured value, floored by the hard limit.

	`MaxCells` living only in ContentConfig is not a cap, because that is the file a designer
	edits to tune content. The limit in GameConfig is the actual bound and is checked here as
	well as at the query boundary.
]]
local function cellCeiling(definition: Types.ChainDefinition): number
	return math.min(definition.MaxCells, GameConfig.Limits.MaxCellsPerChainEvent)
end

-- === Arming ================================================================

local function canArmHere(cell: IceFieldService.Cell, chainKey: string, now: number): boolean
	if cell.ChainKey ~= nil or not cell.Alive then
		return false
	end
	if now < cell.ChainArmableAt then
		return false
	end

	-- Keep seeds of the same chain apart, so two Lava Capsules cannot arm on top of each
	-- other and fire as one indistinguishable blast.
	local spacing = ChainConfig.MinSeedSpacingStuds
	local spacingSquared = spacing * spacing
	for _, other in IceFieldService.getZoneCells(cell.ZoneKey) do
		if other.ChainKey == chainKey then
			local delta = other.Position - cell.Position
			if delta.X * delta.X + delta.Z * delta.Z < spacingSquared then
				return false
			end
		end
	end

	return true
end

--[[
	One arming sweep over one zone.

	Standing caps rather than arming chance alone are what actually bound chain frequency:
	without them the rate would scale with how fast a player clears the field, so a stronger
	player would see proportionally more chains for free.
]]
-- Variadic return type so `local ok, err = pcall(armZone, ...)` has a second value to bind,
-- the same reason ZoneService.patrol is declared this way. Nothing is ever returned.
local function armZone(zoneKey: string, now: number): ...any
	local cells = IceFieldService.getZoneCells(zoneKey)
	if #cells == 0 then
		return
	end

	for _, definition in ContentConfig.Chains do
		if definition.Zone ~= nil and definition.Zone ~= zoneKey then
			continue
		end

		local cap = ChainConfig.MaxArmedPerZone[definition.Key] or 0
		local armed = IceFieldService.countArmed(zoneKey, definition.Key)
		if armed >= cap then
			continue
		end

		local chance = ChainConfig.ArmChancePerSweep[definition.Key] or 0
		if chance <= 0 or rng:NextNumber() >= chance then
			continue
		end

		-- One candidate per sweep per chain, picked at random rather than scanned in order so
		-- seeds do not cluster at the low-index corner of the grid.
		local candidate = cells[rng:NextInteger(1, #cells)]
		if candidate and canArmHere(candidate, definition.Key, now) then
			IceFieldService.setChainSeed(candidate, definition.Key)
			stats.Armed += 1
		end
	end
end

-- === Resolution ============================================================

--[[
	Resolves the chain for a set of seeds destroyed in one melt event.

	Returns nil when there is nothing to fire. Never yields, so it can run inside the melt
	pulse without delaying the reply.
]]
function ChainService.resolveFromSeeds(
	player: Player,
	zoneKey: string,
	meltStats: Types.DerivedStats,
	seeds: { IceFieldService.Cell }
): ChainOutcome?
	if #seeds == 0 then
		return nil
	end

	--[[
		Pick the highest-tier seed and consume every other one without firing it.

		Consuming the rest is what stops a later pulse replaying them: after this, none of them
		is a seed any more, so there is no pending state left to trigger.
	]]
	local chosen: IceFieldService.Cell? = nil
	local chosenRank = -1
	for _, cell in seeds do
		local key = IceFieldService.getSeedKey(cell)
		local rank = if key then (tierRank[key] or 0) else -1
		if key and rank > chosenRank then
			chosen = cell
			chosenRank = rank
		end
	end

	if not chosen then
		return nil
	end

	local chainKey = IceFieldService.getSeedKey(chosen)
	if not chainKey then
		return nil
	end
	local definition = definitionByKey[chainKey]
	if not definition then
		return nil
	end

	-- Consume every seed involved, chosen one included, before a single cell is damaged.
	for _, cell in seeds do
		if IceFieldService.getSeedKey(cell) ~= nil then
			if cell ~= chosen then
				stats.SeedsConsumedWithoutFiring += 1
			end
			IceFieldService.clearChainSeed(cell, ChainConfig.SeedCooldownSeconds)
		end
	end

	local ceiling = cellCeiling(definition)
	local targets =
		IceFieldService.queryCellsNearest(zoneKey, chosen.Position, definition.Radius, ceiling)

	local results: { Types.MeltCellResult } = {}
	local credited = 0
	local heat = 0

	for _, cell in targets do
		-- Re-checked independently of the query cap, so the ceiling holds even if the query
		-- ever returned more than it was asked for.
		if credited >= ceiling then
			break
		end

		--[[
			Any seed the blast passes over is cleared before it is destroyed. That is what
			makes non-cascade structural: propagation never calls the trigger path, and it
			leaves no armed cell behind for the next pulse to catch.
		]]
		if IceFieldService.getSeedKey(cell) ~= nil then
			IceFieldService.clearChainSeed(cell, ChainConfig.SeedCooldownSeconds)
		end

		-- Exactly enough to kill it. damageCell returns true only on the alive-to-dead
		-- transition, so a cell already dead this frame credits nothing.
		if IceFieldService.damageCell(cell, cell.Durability) then
			credited += 1
			local critical = rng:NextNumber() < meltStats.CritChance
			heat += StatMath.heatForCell(meltStats, zoneKey, critical)

			table.insert(results, {
				CellId = cell.Id,
				Damage = cell.MaxDurability,
				Destroyed = true,
				Critical = critical,
				Chain = true,
			})
		end
	end

	if credited == 0 then
		return nil
	end

	-- Ceiling derived from the cap rather than trusted from the sum, so no combination of
	-- multipliers can produce an absurd single payout.
	local maxHeat = ceiling * StatMath.heatForCell(meltStats, zoneKey, true)
	heat = Validate.clampFinite(heat, 0, math.min(maxHeat, BalanceConfig.Melt.MaxHeatPerPulse))

	if heat > 0 then
		EconomyService.grant(player, heat, "ChainReaction")
	end

	stats.Fired += 1
	stats.CellsDestroyed += credited
	stats.HeatGranted += heat
	stats.ByChain[chainKey] = (stats.ByChain[chainKey] or 0) + 1

	--[[
		One analytics event per chain, never one per cell, with the cell count bucketed. Raw
		counts would be 120 x 3 chains x 3 zones of cardinality; bucketed it is a few dozen.
	]]
	local bucket = if credited <= 5
		then "1-5"
		elseif credited <= 15 then "6-15"
		elseif credited <= 40 then "16-40"
		elseif credited <= 80 then "41-80"
		else "81+"

	AnalyticsService.logEvent(player, "ChainReaction", {
		ChainKey = chainKey,
		ZoneKey = zoneKey,
		Cells = bucket,
	})

	AnnouncementService.announceChain(player, chainKey, zoneKey, credited)

	return {
		ChainKey = chainKey,
		OriginCellId = chosen.Id,
		Credited = credited,
		HeatAwarded = heat,
		Cells = results,
	}
end

function ChainService.getStats()
	return {
		Armed = stats.Armed,
		Fired = stats.Fired,
		CellsDestroyed = stats.CellsDestroyed,
		HeatGranted = stats.HeatGranted,
		SeedsConsumedWithoutFiring = stats.SeedsConsumedWithoutFiring,
		ByChain = table.clone(stats.ByChain),
		ArmedNow = IceFieldService.countArmed(nil, nil),
	}
end

--[[
	Arms a seed on the nearest eligible cell to a position. Development only, used by the dev
	commands so a chain can be tested without waiting for the sweep.
]]
function ChainService.armNearest(zoneKey: string, position: Vector3, chainKey: string): number?
	if not definitionByKey[chainKey] then
		return nil
	end

	local nearest = IceFieldService.queryCellsNearest(zoneKey, position, 200, 1)
	local cell = nearest[1]
	if not cell then
		return nil
	end

	IceFieldService.setChainSeed(cell, chainKey)
	stats.Armed += 1
	return cell.Id
end

function ChainService.Start()
	--[[
		One arming sweep for every zone, rather than a timer per chain or per cell. Matches how
		respawns are batched: hundreds of scheduler entries for work that batches trivially is
		the thing this codebase already decided against.
	]]
	task.spawn(function()
		while true do
			task.wait(ChainConfig.ArmSweepSeconds)
			local now = os.clock()
			for _, zoneKey in ContentConfig.ZoneOrder do
				local ok, err = pcall(armZone, zoneKey, now)
				if not ok then
					warn(
						string.format(
							"[IceMelt] ChainService: arming sweep failed for %s: %s",
							zoneKey,
							tostring(err)
						)
					)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function() end)
end

return ChainService
