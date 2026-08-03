--!strict

--[[
	StatsService

	The one server module that turns a profile into effective stats.

	Before this existed MeltService computed its own stats inline. That was fine while melt
	was the only consumer, but upgrades, tools, the HUD, and walk speed all need the same
	numbers, and four copies of "what is this player's radius" is four places to forget a
	future pass multiplier or cap.

	Results are cached per player and invalidated on any change that could affect them.
	The cache matters: stats are read on every melt pulse, up to twelve times a second per
	player, and recomputing seven upgrade curves each time is pure waste.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))

local DataService = require(script.Parent:WaitForChild("DataService", 10))

type DerivedStats = Types.DerivedStats

local StatsService = {
	Name = "StatsService",
	-- After DataService, before anything that reads stats.
	Priority = 15,
}

-- Cached per player, per zone: radius and luck depend on the zone the player is in.
local cache: { [Player]: { [string]: DerivedStats } } = {}

--[[
	Effective stats for a player in a zone. Cached until invalidated.
]]
function StatsService.get(player: Player, zoneKey: string): DerivedStats?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end

	local perZone = cache[player]
	if not perZone then
		perZone = {}
		cache[player] = perZone
	end

	local cached = perZone[zoneKey]
	if cached then
		return cached
	end

	local computed =
		StatMath.computeMeltStats(profile.Upgrades, profile.EquippedTool, zoneKey, profile.Embers)
	perZone[zoneKey] = computed
	return computed
end

--[[
	Drops the cache for a player. Must be called after any upgrade, tool, or zone change.
	Cheap: the next read recomputes.
]]
function StatsService.invalidate(player: Player)
	cache[player] = nil
end

--[[
	The stat block sent to the client, for the player's current zone.

	Uses the starting zone as the reference so the HUD has stable numbers to show even
	before zone travel exists. Phase 05 will pass the player's actual zone.
]]
function StatsService.getForDisplay(player: Player, zoneKey: string): DerivedStats
	local stats = StatsService.get(player, zoneKey)
	if stats then
		return stats
	end

	return {
		Damage = 0,
		Radius = 0,
		HeatMultiplier = 0,
		CritChance = 0,
		Luck = 0,
		WalkSpeed = 16,
		AutoRate = 0,
		EmberMultiplier = 1,
	}
end

function StatsService.Start()
	Players.PlayerRemoving:Connect(function(player)
		cache[player] = nil
	end)
end

return StatsService
