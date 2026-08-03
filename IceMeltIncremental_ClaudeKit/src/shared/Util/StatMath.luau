--!strict

--[[
	StatMath

	The single place that turns upgrade levels, an equipped tool, and a zone into effective
	stats.

	Shared deliberately. The client needs the same numbers to draw an honest melt radius and
	preview an upgrade, and the server needs them to decide what actually happens. Two
	implementations would drift, and the drift would look like an exploit.

	Sharing the maths is not the same as trusting the client. The server always calls these
	with values it read from the authoritative profile; a client calling them with invented
	levels only lies to itself.

	Order of operations is fixed here and documented in BalanceConfig:
	    damage = PowerStat * ToolPower
	    heat   = CellHeat * ValueStat * ZoneHeat * (CriticalMultiplier if critical)
	Radius and luck resolve the same way and are clamped before use.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(script.Parent:WaitForChild("Validate", 10))

type UpgradeLevels = Types.UpgradeLevels

local StatMath = {}

export type MeltStats = {
	Damage: number,
	Radius: number,
	HeatMultiplier: number,
	CritChance: number,
	Luck: number,
	WalkSpeed: number,
	AutoRate: number,
}

--[[
	Applies one upgrade's scaling. Levels are clamped to the configured cap first, so a
	corrupt or tampered level cannot produce an absurd stat even if it reached the profile.
]]
function StatMath.upgradeEffect(key: string, level: number): number
	local definition = BalanceConfig.Upgrades[key]
	if not definition then
		return 0
	end

	local safeLevel = Validate.clampFinite(level, 0, definition.Cap)

	if definition.Scaling == "Multiplier" then
		return definition.BaseEffect * (definition.PerLevel ^ safeLevel)
	end
	return definition.BaseEffect + definition.PerLevel * safeLevel
end

--[[
	Cost of the next level: floor(BaseCost * Growth ^ currentLevel).
	Returns nil when the upgrade is already capped, which callers must treat as "cannot
	buy" rather than "free".
]]
function StatMath.upgradeCost(key: string, currentLevel: number): number?
	local definition = BalanceConfig.Upgrades[key]
	if not definition then
		return nil
	end

	local safeLevel = Validate.clampFinite(currentLevel, 0, definition.Cap)
	if safeLevel >= definition.Cap then
		return nil
	end

	return math.floor(definition.BaseCost * (definition.Growth ^ safeLevel))
end

function StatMath.getTool(index: number): Types.ToolDefinition
	local clamped = math.clamp(math.floor(index), 1, #ContentConfig.Tools)
	return ContentConfig.Tools[clamped]
end

--[[
	Full stat block for a player in a zone.

	Every result is clamped: the ceilings in BalanceConfig.Melt are the last line of defence
	against any combination of upgrades, tools, and future boosts producing a runaway value.
]]
function StatMath.computeMeltStats(
	upgrades: UpgradeLevels,
	toolIndex: number,
	zoneKey: string
): MeltStats
	local tool = StatMath.getTool(toolIndex)
	local zone = ContentConfig.Zones[zoneKey]
	local melt = BalanceConfig.Melt

	local power = StatMath.upgradeEffect("Power", upgrades.Power)
	local radius = StatMath.upgradeEffect("Radius", upgrades.Radius)
	local value = StatMath.upgradeEffect("Value", upgrades.Value)
	local crit = StatMath.upgradeEffect("Crit", upgrades.Crit)
	local luck = StatMath.upgradeEffect("Luck", upgrades.Luck)
	local speed = StatMath.upgradeEffect("Speed", upgrades.Speed)
	local auto = StatMath.upgradeEffect("Auto", upgrades.Auto)

	local zoneLuck = if zone then zone.Luck else 1

	return {
		Damage = Validate.clampFinite(power * tool.Power, 0, 1e12),
		Radius = Validate.clampFinite(radius + tool.Radius, 1, melt.MaxRadiusStuds),
		HeatMultiplier = Validate.clampFinite(value, 0, 1e9),
		-- Crit is a probability; anything outside [0, 1] is meaningless.
		CritChance = Validate.clampFinite(crit, 0, 1),
		Luck = Validate.clampFinite(luck * zoneLuck, 0, 1e6),
		WalkSpeed = Validate.clampFinite(speed, 8, 100),
		AutoRate = Validate.clampFinite(auto, 0, 20),
	}
end

--[[
	Heat for destroying one cell. Kept separate from damage so a chain reaction can award
	cells through the same path a normal melt uses.
]]
function StatMath.heatForCell(stats: MeltStats, zoneKey: string, critical: boolean): number
	local zone = ContentConfig.Zones[zoneKey]
	local base = if zone then zone.Heat else 1

	local heat = base * stats.HeatMultiplier
	if critical then
		heat *= BalanceConfig.Melt.CriticalMultiplier
	end

	return Validate.clampFinite(heat, 0, BalanceConfig.Melt.MaxHeatPerPulse)
end

return table.freeze(StatMath)
