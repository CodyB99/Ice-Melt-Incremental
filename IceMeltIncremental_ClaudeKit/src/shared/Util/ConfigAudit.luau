--!strict

--[[
	ConfigAudit

	Development assertions over the configuration modules. Configuration drift is the
	failure mode this project is most exposed to: content lives in tables, so a renamed
	zone or a mistyped upgrade key produces silently wrong gameplay rather than a crash.

	Runs once at server startup. In Development and Test every problem is reported; in
	Production the audit still runs but only Errors are logged, so a cosmetic warning
	cannot spam a live server.

	Severity:
	  "Error"   -- will produce wrong behaviour. Fix before shipping.
	  "Warning" -- suspicious but survivable.
]]

local BalanceConfig = require(script.Parent.Parent.Config.BalanceConfig)
local ContentConfig = require(script.Parent.Parent.Config.ContentConfig)
local MonetizationConfig = require(script.Parent.Parent.Config.MonetizationConfig)
local RemoteNames = require(script.Parent.Parent.Config.RemoteNames)
local Validate = require(script.Parent.Validate)
local WorldConfig = require(script.Parent.Parent.Config.WorldConfig)

export type Severity = "Error" | "Warning"

export type Problem = {
	Severity: Severity,
	Source: string,
	Message: string,
}

export type AuditReport = {
	Problems: { Problem },
	ErrorCount: number,
	WarningCount: number,
}

local ConfigAudit = {}

local UPGRADE_KEYS = table.freeze({ "Power", "Radius", "Value", "Speed", "Crit", "Luck", "Auto" })

local function add(problems: { Problem }, severity: Severity, source: string, message: string)
	table.insert(
		problems,
		table.freeze({ Severity = severity, Source = source, Message = message })
	)
end

local function auditUpgrades(problems: { Problem })
	local seen: { [string]: boolean } = {}

	for _, key in BalanceConfig.UpgradeOrder do
		if seen[key] then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("UpgradeOrder lists %q twice", key)
			)
		end
		seen[key] = true

		local definition = BalanceConfig.Upgrades[key]
		if not definition then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("UpgradeOrder references %q, which has no definition", key)
			)
			continue
		end

		if definition.Key ~= key then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format(
					"Upgrade %q has mismatched Key field %q",
					key,
					tostring(definition.Key)
				)
			)
		end
		if not Validate.isFiniteInRange(definition.BaseCost, 0, math.huge - 1) then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Upgrade %q has a non-finite BaseCost", key)
			)
		end
		if not Validate.isFiniteInRange(definition.Growth, 1, 10) then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format(
					"Upgrade %q Growth must be between 1 and 10, got %s",
					key,
					tostring(definition.Growth)
				)
			)
		end
		if not Validate.isIntegerInRange(definition.Cap, 1, 10000) then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Upgrade %q has an implausible Cap", key)
			)
		end
		if definition.Scaling == "Multiplier" and definition.PerLevel <= 1 then
			add(
				problems,
				"Warning",
				"BalanceConfig",
				string.format(
					"Upgrade %q scales by multiplication but PerLevel <= 1, so it never improves",
					key
				)
			)
		end
	end

	-- Every key in the profile's Upgrades table must have a definition, or a purchase
	-- would write a level nothing ever reads.
	for _, key in UPGRADE_KEYS do
		if not seen[key] then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Profile upgrade %q is missing from UpgradeOrder", key)
			)
		end
	end
end

local function auditTools(problems: { Problem })
	local seenKeys: { [string]: boolean } = {}
	local previousCost = -1

	for index, tool in ContentConfig.Tools do
		if seenKeys[tool.Key] then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Duplicate tool key %q", tool.Key)
			)
		end
		seenKeys[tool.Key] = true

		if not Validate.isFiniteInRange(tool.Cost, 0, math.huge - 1) then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Tool %q has a non-finite Cost", tool.Key)
			)
		elseif tool.Cost <= previousCost then
			-- Progression gates assume ascending cost; out-of-order entries make a later
			-- tool cheaper than an earlier one.
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Tool %q (index %d) does not cost more than the previous tool",
					tool.Key,
					index
				)
			)
		end
		previousCost = tool.Cost

		if tool.Power <= 0 then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Tool %q has non-positive Power", tool.Key)
			)
		end
	end

	if #ContentConfig.Tools ~= 8 then
		add(
			problems,
			"Warning",
			"ContentConfig",
			string.format("MVP scope is 8 tools, found %d", #ContentConfig.Tools)
		)
	end
end

local function auditZones(problems: { Problem })
	for _, zoneKey in ContentConfig.ZoneOrder do
		local zone = ContentConfig.Zones[zoneKey]
		if not zone then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("ZoneOrder references %q, which has no definition", zoneKey)
			)
			continue
		end

		if zone.Durability <= 0 or zone.Heat <= 0 then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Zone %q must have positive Durability and Heat", zoneKey)
			)
		end
		if zone.RespawnSeconds <= 0 then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Zone %q must have a positive RespawnSeconds", zoneKey)
			)
		end
	end

	if ContentConfig.Zones[ContentConfig.StartingZone] == nil then
		add(
			problems,
			"Error",
			"ContentConfig",
			string.format("StartingZone %q has no definition", tostring(ContentConfig.StartingZone))
		)
	elseif ContentConfig.Zones[ContentConfig.StartingZone].Cost ~= 0 then
		add(
			problems,
			"Error",
			"ContentConfig",
			"StartingZone must cost 0 or a new player cannot play"
		)
	end

	-- The world skeleton and the content catalogue must agree, in both directions.
	for _, zoneKey in WorldConfig.ZoneOrder do
		if ContentConfig.Zones[zoneKey] == nil then
			add(
				problems,
				"Error",
				"WorldConfig",
				string.format(
					"WorldConfig builds zone %q, which ContentConfig does not define",
					zoneKey
				)
			)
		end
		if WorldConfig.Zones[zoneKey] == nil then
			add(
				problems,
				"Error",
				"WorldConfig",
				string.format("ZoneOrder lists %q, which has no layout", zoneKey)
			)
		end
	end
	for _, zoneKey in ContentConfig.ZoneOrder do
		if WorldConfig.Zones[zoneKey] == nil then
			add(
				problems,
				"Warning",
				"WorldConfig",
				string.format(
					"Zone %q is defined in content but has no world layout, so it cannot be entered",
					zoneKey
				)
			)
		end
	end
end

local function auditDiscoveries(problems: { Problem })
	local seenKeys: { [string]: boolean } = {}
	local perZone: { [string]: number } = {}

	for _, discovery in ContentConfig.Discoveries do
		if seenKeys[discovery.Key] then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Duplicate discovery key %q", discovery.Key)
			)
		end
		seenKeys[discovery.Key] = true

		if ContentConfig.Zones[discovery.Zone] == nil then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Discovery %q references unknown zone %q",
					discovery.Key,
					tostring(discovery.Zone)
				)
			)
		else
			perZone[discovery.Zone] = (perZone[discovery.Zone] or 0) + 1
		end

		if BalanceConfig.Discovery.RarityWeights[discovery.Rarity] == nil then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Discovery %q has unknown rarity %q",
					discovery.Key,
					tostring(discovery.Rarity)
				)
			)
		end
	end

	if #ContentConfig.Discoveries ~= 20 then
		add(
			problems,
			"Warning",
			"ContentConfig",
			string.format("MVP scope is 20 discoveries, found %d", #ContentConfig.Discoveries)
		)
	end

	-- A zone with no discoveries would roll forever and never award anything.
	for _, zoneKey in ContentConfig.ZoneOrder do
		if (perZone[zoneKey] or 0) == 0 then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Zone %q has no discoveries", zoneKey)
			)
		end
	end

	for _, rarity in BalanceConfig.Discovery.RarityOrder do
		local weight = BalanceConfig.Discovery.RarityWeights[rarity]
		if weight == nil then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("RarityOrder lists %q with no weight", rarity)
			)
		elseif not Validate.isFiniteInRange(weight, 0, 1000) or weight <= 0 then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Rarity %q has an invalid weight", rarity)
			)
		end
	end
end

--[[
	Marketplace IDs must be a whole positive number or exactly 0. A 0 means "not created
	yet" and must disable the item safely; anything else (a float, a negative, a string
	pasted from the dashboard with stray characters) would reach MarketplaceService and
	fail at the worst possible moment.
]]
local function auditMonetization(problems: { Problem })
	-- Annotated so both entries share one element type. Without it the array type is
	-- inferred from Passes alone and Products fails to match.
	local groups: { { Label: string, Map: { [string]: number } } } = {
		{ Label = "Passes", Map = MonetizationConfig.Passes },
		{ Label = "Products", Map = MonetizationConfig.Products },
	}

	local unconfigured = 0

	for _, group in groups do
		for key, id in group.Map do
			if not Validate.isIntegerInRange(id, 0, 1e15) then
				add(
					problems,
					"Error",
					"MonetizationConfig",
					string.format("%s.%s has a malformed ID: %s", group.Label, key, tostring(id))
				)
			elseif id == 0 then
				unconfigured += 1
			end
		end
	end

	if unconfigured > 0 then
		-- Expected until the owner creates them in Creator Dashboard, so this is a
		-- warning with a count rather than one line per item.
		add(
			problems,
			"Warning",
			"MonetizationConfig",
			string.format(
				"%d marketplace ID(s) are still 0 and stay disabled (expected until Phase 09)",
				unconfigured
			)
		)
	end
end

local function auditRemotes(problems: { Problem })
	local seen: { [string]: boolean } = {}

	for _, remoteSpec in RemoteNames.Specs do
		if seen[remoteSpec.Name] then
			add(
				problems,
				"Error",
				"RemoteNames",
				string.format("Duplicate remote %q", remoteSpec.Name)
			)
		end
		seen[remoteSpec.Name] = true

		if
			remoteSpec.Direction ~= "ClientToServer"
			and remoteSpec.Direction ~= "ServerToClient"
		then
			add(
				problems,
				"Error",
				"RemoteNames",
				string.format(
					"Remote %q has invalid direction %q",
					remoteSpec.Name,
					tostring(remoteSpec.Direction)
				)
			)
		end

		-- A generic dispatch remote would let a client name the action, which is exactly
		-- the shape the phase acceptance criteria forbid.
		local lowered = string.lower(remoteSpec.Name)
		if
			remoteSpec.Direction == "ClientToServer"
			and (
				string.find(lowered, "command")
				or string.find(lowered, "dispatch")
				or lowered == "invoke"
			)
		then
			add(
				problems,
				"Error",
				"RemoteNames",
				string.format(
					"Remote %q looks like a generic client command channel",
					remoteSpec.Name
				)
			)
		end
	end
end

--[[
	Runs every audit. Never throws: the caller decides whether problems are fatal, so a
	single bad config value cannot take down a live server on its own.
]]
function ConfigAudit.run(): AuditReport
	local problems: { Problem } = {}

	auditUpgrades(problems)
	auditTools(problems)
	auditZones(problems)
	auditDiscoveries(problems)
	auditMonetization(problems)
	auditRemotes(problems)

	local errorCount = 0
	local warningCount = 0
	for _, problem in problems do
		if problem.Severity == "Error" then
			errorCount += 1
		else
			warningCount += 1
		end
	end

	return {
		Problems = problems,
		ErrorCount = errorCount,
		WarningCount = warningCount,
	}
end

--[[
	Logs a report. `verbose` is false in Production, where only Errors are worth the noise.
]]
function ConfigAudit.log(report: AuditReport, verbose: boolean)
	for _, problem in report.Problems do
		if problem.Severity == "Error" then
			warn(string.format("[IceMelt] config error: %s: %s", problem.Source, problem.Message))
		elseif verbose then
			warn(string.format("[IceMelt] config warning: %s: %s", problem.Source, problem.Message))
		end
	end
end

return table.freeze(ConfigAudit)
