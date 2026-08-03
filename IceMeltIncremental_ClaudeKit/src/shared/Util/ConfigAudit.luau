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
local ChainConfig = require(script.Parent.Parent.Config.ChainConfig)
local ContentConfig = require(script.Parent.Parent.Config.ContentConfig)
local DiscoveryMath = require(script.Parent.DiscoveryMath)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
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
	Chain definitions.

	`MaxCells` is checked against the ceiling in GameConfig.Limits rather than trusted, because
	ContentConfig is the file a designer edits to tune content and a cap that lives there is
	not a cap.

	`Announce` is checked for being strictly boolean, as an Error rather than a Warning: in
	Luau the string "false" is truthy, so a value typed as text would announce every chain to
	the whole server while reading as if it were switched off.
]]
local function auditChains(problems: { Problem })
	local seen: { [string]: boolean } = {}
	local largest = 0

	for _, definition in ContentConfig.Chains do
		if seen[definition.Key] then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Duplicate chain key %q", definition.Key)
			)
		end
		seen[definition.Key] = true

		if not Validate.isFiniteInRange(definition.Radius, 1, 1000) then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format("Chain %q has an implausible Radius", definition.Key)
			)
		end

		if
			not Validate.isIntegerInRange(
				definition.MaxCells,
				1,
				GameConfig.Limits.MaxCellsPerChainEvent
			)
		then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Chain %q MaxCells must be a whole number no greater than the "
						.. "MaxCellsPerChainEvent limit of %d",
					definition.Key,
					GameConfig.Limits.MaxCellsPerChainEvent
				)
			)
		elseif definition.MaxCells > largest then
			largest = definition.MaxCells
		end

		if type(definition.Announce) ~= "boolean" then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Chain %q Announce must be a boolean, got %s. A non-empty string is truthy "
						.. "in Luau and would announce every one of these to the whole server.",
					definition.Key,
					typeof(definition.Announce)
				)
			)
		end

		if definition.Zone ~= nil and ContentConfig.Zones[definition.Zone] == nil then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Chain %q is restricted to unknown zone %q",
					definition.Key,
					tostring(definition.Zone)
				)
			)
		end

		-- An announcing chain that can arm anywhere would put the rarest spectacle in the
		-- tutorial zone. docs/04 restricts the announcing one to the City.
		if definition.Announce and definition.Zone == nil then
			add(
				problems,
				"Warning",
				"ContentConfig",
				string.format(
					"Chain %q announces to the whole server but is not restricted to a zone",
					definition.Key
				)
			)
		end

		if ChainConfig.ArmChancePerSweep[definition.Key] == nil then
			add(
				problems,
				"Error",
				"ChainConfig",
				string.format("Chain %q has no ArmChancePerSweep entry", definition.Key)
			)
		end
		if ChainConfig.MaxArmedPerZone[definition.Key] == nil then
			add(
				problems,
				"Error",
				"ChainConfig",
				string.format("Chain %q has no MaxArmedPerZone entry", definition.Key)
			)
		end
	end

	-- A pulse plus the largest chain it can trigger has to fit inside one batched result.
	local worst = GameConfig.Limits.MaxCellsPerPulse + largest
	if worst > GameConfig.Limits.MaxCellsPerResult then
		add(
			problems,
			"Error",
			"GameConfig",
			string.format(
				"A full pulse (%d cells) plus the largest chain (%d) is %d, above the "
					.. "MaxCellsPerResult limit of %d",
				GameConfig.Limits.MaxCellsPerPulse,
				largest,
				worst,
				GameConfig.Limits.MaxCellsPerResult
			)
		)
	end
end

--[[
	Proves the discovery weight table is well formed at sampled luck values.

	This is the check that makes "luck cannot exceed configured caps or create invalid weights"
	a demonstrated property rather than an assertion. It evaluates the very function the roll
	uses, which is the whole reason that function lives in a shared module: a second
	implementation here would be the drift this audit exists to catch.

	The last samples deliberately go past the configured ceiling and into non-finite values, to
	prove the clamp holds and that a corrupt luck degrades to the documented baseline rather
	than poisoning the table.
]]
local function auditDiscoveryWeights(problems: { Problem })
	local maxLuck = BalanceConfig.Discovery.MaxLuck
	local samples = { 0, 1, 2, 10, maxLuck, maxLuck * 4, -1, 0 / 0 }

	for _, zoneKey in ContentConfig.ZoneOrder do
		for _, luck in samples do
			local rows = DiscoveryMath.rarityRows(zoneKey, luck)

			if #rows == 0 then
				add(
					problems,
					"Error",
					"ContentConfig",
					string.format(
						"Zone %q produced no discovery weights at luck %s",
						zoneKey,
						tostring(luck)
					)
				)
				continue
			end

			local total = 0
			for _, row in rows do
				if
					not Validate.isFiniteInRange(
						row.Weight,
						0,
						BalanceConfig.Discovery.MaxRarityWeight
					)
				then
					add(
						problems,
						"Error",
						"BalanceConfig",
						string.format(
							"Zone %q rarity %q produced weight %s at luck %s, outside [0, %s]",
							zoneKey,
							row.Rarity,
							tostring(row.Weight),
							tostring(luck),
							tostring(BalanceConfig.Discovery.MaxRarityWeight)
						)
					)
				end
				if not Validate.isFiniteInRange(row.Probability, 0, 1) then
					add(
						problems,
						"Error",
						"BalanceConfig",
						string.format(
							"Zone %q rarity %q produced probability %s at luck %s",
							zoneKey,
							row.Rarity,
							tostring(row.Probability),
							tostring(luck)
						)
					)
				end
				total += row.Probability
			end

			if math.abs(total - 1) > 1e-6 then
				add(
					problems,
					"Error",
					"BalanceConfig",
					string.format(
						"Zone %q probabilities sum to %s at luck %s, not 1",
						zoneKey,
						tostring(total),
						tostring(luck)
					)
				)
			end

			-- Common must survive every luck value. This is the floor that stops a high-luck
			-- player being locked out of the commonest tier entirely.
			local commonKey = BalanceConfig.Discovery.RarityOrder[1]
			for _, row in rows do
				if row.Rarity == commonKey and row.Probability <= 0 then
					add(
						problems,
						"Error",
						"BalanceConfig",
						string.format(
							"Zone %q drove %s to zero at luck %s",
							zoneKey,
							commonKey,
							tostring(luck)
						)
					)
				end
			end
		end
	end

	-- The floor exists to protect Common specifically, so its luck exponent must be zero.
	local commonKey = BalanceConfig.Discovery.RarityOrder[1]
	if BalanceConfig.Discovery.RarityLuckExponent[commonKey] ~= 0 then
		add(
			problems,
			"Error",
			"BalanceConfig",
			string.format(
				"RarityLuckExponent[%q] must be 0 so luck cannot scale the commonest tier",
				commonKey
			)
		)
	end

	if BalanceConfig.Discovery.MinLuck <= 0 then
		add(
			problems,
			"Error",
			"BalanceConfig",
			"Discovery.MinLuck must be above 0. clampFinite returns the minimum for a "
				.. "non-finite input, so a floor of 0 would silently lock a corrupt luck to "
				.. "100% Common."
		)
	end

	-- Every rarity that carries weight should be reachable somewhere, or its weight is a lie.
	local reachable: { [string]: boolean } = {}
	for _, zoneKey in ContentConfig.ZoneOrder do
		for _, rarity in DiscoveryMath.zoneRarities(zoneKey) do
			reachable[rarity] = true
		end
	end
	for _, rarity in BalanceConfig.Discovery.RarityOrder do
		if not reachable[rarity] then
			add(
				problems,
				"Warning",
				"ContentConfig",
				string.format(
					"Rarity %q has a weight but no discovery in any zone, so it can never be rolled",
					rarity
				)
			)
		end
		if BalanceConfig.Discovery.RarityLuckExponent[rarity] == nil then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Rarity %q has no RarityLuckExponent entry", rarity)
			)
		end
		if BalanceConfig.Discovery.DuplicateHeatCells[rarity] == nil then
			add(
				problems,
				"Error",
				"BalanceConfig",
				string.format("Rarity %q has no DuplicateHeatCells entry", rarity)
			)
		end
	end

	-- Every zone needs its commonest tier present, or the roll's downward fallback has
	-- nothing to land on.
	for _, zoneKey in ContentConfig.ZoneOrder do
		if #DiscoveryMath.zoneDiscoveries(zoneKey, commonKey) == 0 then
			add(
				problems,
				"Error",
				"ContentConfig",
				string.format(
					"Zone %q has no %s discovery, so the roll fallback has nothing to land on",
					zoneKey,
					commonKey
				)
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
	local broadcasts = 0

	for _, remoteSpec in RemoteNames.Specs do
		--[[
			Broadcast is the permission that lets a remote reach every client at once. Every
			other outbound remote carries one player's data, so a broadcast flag on the wrong
			one would publish that data to the whole server.
		]]
		if remoteSpec.Broadcast then
			broadcasts += 1
			if remoteSpec.Direction ~= "ServerToClient" then
				add(
					problems,
					"Error",
					"RemoteNames",
					string.format(
						"Remote %q is declared Broadcast but is %s. Only outbound remotes can "
							.. "be broadcast.",
						remoteSpec.Name,
						remoteSpec.Direction
					)
				)
			end
		end

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

	--[[
		Broadcast remotes are meant to be exceptional. More than one is not wrong on its own,
		but it is worth surfacing: every extra one is another channel that reaches every client
		and therefore another place a per-player value could leak.
	]]
	if broadcasts > 1 then
		add(
			problems,
			"Warning",
			"RemoteNames",
			string.format(
				"%d remotes are declared Broadcast. Each one reaches every client, so keep the "
					.. "set as small as possible.",
				broadcasts
			)
		)
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
	auditDiscoveryWeights(problems)
	auditChains(problems)
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
