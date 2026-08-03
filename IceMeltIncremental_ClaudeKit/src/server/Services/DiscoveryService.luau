--!strict

--[[
	DiscoveryService

	Weighted rolls, collection state, and discovery rewards. docs/02 names this service.

	The whole roll is driven from `DiscoveryMath`, which is pure and shared. This module owns
	only the impure parts: the RNG, the profile write, the Heat grant, analytics, and the
	announcement. That split is what lets ConfigAudit prove the weight table at startup and a
	dev command sample two hundred thousand rolls without a player.

	Ordering, which is an explicit phase requirement ("award/save before showing reveal UI"):

	    1. roll                     -- pure, from the server's own destroyed-cell count
	    2. write the profile        -- the award exists from here on
	    3. grant Heat               -- through EconomyService, so it lands in the ledger
	    4. schedule a durable save  -- throttled, so a crash cannot cost the discovery
	    5. analytics, announcement
	    6. return, and only then does MeltService put the key in the reply

	Nothing in steps 1-5 yields, so a player who disconnects mid-pulse either has the award
	written or never rolled at all. The reveal card is a consequence of the award, never a
	precondition for it — docs/04 requires that a player cannot lose a discovery to a closed
	UI or a dropped connection.

	The roll is per destroyed CELL, not per pulse. A per-pulse roll would be a client-controlled
	rate, because the client chooses its pulse frequency up to the configured ceiling. That is
	the same class of bug Phase 04 already fixed once for damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local DiscoveryMath = require(UtilFolder:WaitForChild("DiscoveryMath", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService", 10))
local AnnouncementService = require(script.Parent:WaitForChild("AnnouncementService", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))

local DiscoveryService = {
	Name = "DiscoveryService",
	-- After IceFieldService (20), before MeltService (30), which calls into it.
	Priority = 25,
}

export type DiscoveryRoll = {
	Key: string,
	DisplayName: string,
	Rarity: string,
	ZoneKey: string,
	IsNew: boolean,
	HeatAwarded: number,
}

--[[
	Module-local generator, deliberately not the global `math.random`.

	Never seeded from anything world- or client-derived. A cell id, a UserId or the clock would
	all make outcomes predictable to someone who can observe them, and a `math.randomseed` call
	anywhere else in the server VM would otherwise reach this roll. A `Random` object is immune
	to that.
]]
local rng = Random.new()

-- Durable saves are throttled per player: a discovery is worth persisting promptly, but not
-- worth a DataStore write per melt pulse.
local SAVE_INTERVAL_SECONDS = 10
local lastSaveAt: { [Player]: number } = {}
local savePending: { [Player]: boolean } = {}

local stats = {
	Rolls = 0,
	Awarded = 0,
	FirstOfKind = 0,
	Duplicates = 0,
	HeatGranted = 0,
	ByRarity = {} :: { [string]: number },
}

--[[
	Persists soon, without blocking the melt reply.

	`markDirty` alone leaves the award exposed to a crash for up to the autosave interval, and
	a synchronous save would put a yielding DataStore call inside a melt pulse. A throttled
	spawned save is the middle: at most one write every SAVE_INTERVAL_SECONDS per player, and
	the in-flight flag is cleared in the same scope it is set so a failed save cannot wedge it.
]]
local function scheduleSave(player: Player)
	if savePending[player] then
		return
	end

	local now = os.clock()
	local last = lastSaveAt[player] or 0
	local wait = math.max(0, SAVE_INTERVAL_SECONDS - (now - last))

	savePending[player] = true
	task.delay(wait, function()
		savePending[player] = nil
		if not player.Parent or not DataService.isLoaded(player) then
			return
		end
		lastSaveAt[player] = os.clock()
		DataService.save(player)
	end)
end

--[[
	Commits one discovery to a player.

	Shared by the roll and by the dev command, so a forced award goes through exactly the same
	profile write, reward, analytics and announcement path as a real one. Returns nil when the
	profile refused the write, in which case no Heat is granted — the caller cannot pay for an
	award that was never recorded.
]]
function DiscoveryService.award(
	player: Player,
	zoneKey: string,
	stats_: StatMath.MeltStats,
	definition: Types.DiscoveryDefinition
): DiscoveryRoll?
	local granted, isFirst = PlayerStateService.addDiscovery(player, definition.Key)
	if not granted then
		return nil
	end

	--[[
		Reward in zone-cell-equivalents rather than an absolute figure, so it inherits zone
		Heat, the Value upgrade and the Ember multiplier and introduces no new constant into an
		economy that is still under review. Never critical: a discovery is not a melt.
	]]
	local perCell = StatMath.heatForCell(stats_, zoneKey, false)
	local cells = DiscoveryMath.rewardCells(definition.Rarity, isFirst)
	local amount = Validate.clampFinite(perCell * cells, 0, BalanceConfig.Melt.MaxHeatPerPulse)

	if amount > 0 then
		EconomyService.grant(player, amount, "DiscoveryReward")
	end

	scheduleSave(player)

	stats.Awarded += 1
	stats.HeatGranted += amount
	stats.ByRarity[definition.Rarity] = (stats.ByRarity[definition.Rarity] or 0) + 1
	if isFirst then
		stats.FirstOfKind += 1
	else
		stats.Duplicates += 1
	end

	--[[
		The funnel step is gated on the distinct count reaching exactly one, read AFTER the
		write — not on `isFirst`, which is true for the first of EACH of the twenty kinds and
		would log this event up to twenty times per player.
	]]
	if isFirst and PlayerStateService.getDiscoveryCount(player) == 1 then
		AnalyticsService.logEvent(player, "FirstDiscoveryFound", {
			Rarity = definition.Rarity,
			ZoneKey = zoneKey,
		})
	end

	AnalyticsService.logEvent(player, "DiscoveryReward", {
		Rarity = definition.Rarity,
		ZoneKey = zoneKey,
		IsFirst = isFirst,
	})

	AnnouncementService.announceDiscovery(
		player,
		definition.Key,
		definition.Rarity,
		zoneKey,
		isFirst
	)

	-- Annotated so the Rarity union narrows to the plain string this type carries, rather than
	-- failing the exact-match check on the way out.
	local roll: DiscoveryRoll = {
		Key = definition.Key,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		ZoneKey = zoneKey,
		IsNew = isFirst,
		HeatAwarded = amount,
	}
	return roll
end

--[[
	Rolls for one melt event and, on a hit, awards it.

	`meltDestroyed` and `chainDestroyed` are the server's own counts of cells that made the
	alive-to-dead transition. Nothing the client sent influences either.

	Returns nil far more often than not; that is the normal outcome.
]]
function DiscoveryService.rollForMeltEvent(
	player: Player,
	zoneKey: string,
	stats_: StatMath.MeltStats,
	meltDestroyed: number,
	chainDestroyed: number
): DiscoveryRoll?
	if not DataService.isLoaded(player) then
		return nil
	end

	local credited = math.floor((meltDestroyed or 0) + (chainDestroyed or 0))
	if credited <= 0 then
		return nil
	end

	local chance = DiscoveryMath.chanceForCells(credited)
	if chance <= 0 then
		return nil
	end

	stats.Rolls += 1
	if rng:NextNumber() >= chance then
		return nil
	end

	--[[
		Luck comes from the already-computed stat block and nothing else.

		`StatMath.computeMeltStats` has already folded the zone's luck multiplier in, so
		reading `ContentConfig.Zones[zoneKey].Luck` again here would square it and turn the
		City's 2.25 into 5.06. Both values are within easy reach and the wrong one still
		"works", which is why this is a stated prohibition rather than a convention.
	]]
	local definition =
		DiscoveryMath.pickDiscovery(zoneKey, stats_.Luck, rng:NextNumber(), rng:NextNumber())
	if not definition then
		return nil
	end

	return DiscoveryService.award(player, zoneKey, stats_, definition)
end

function DiscoveryService.getStats()
	return {
		Rolls = stats.Rolls,
		Awarded = stats.Awarded,
		FirstOfKind = stats.FirstOfKind,
		Duplicates = stats.Duplicates,
		HeatGranted = stats.HeatGranted,
		ByRarity = table.clone(stats.ByRarity),
	}
end

function DiscoveryService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastSaveAt[player] = nil
		savePending[player] = nil
	end)
end

return DiscoveryService
