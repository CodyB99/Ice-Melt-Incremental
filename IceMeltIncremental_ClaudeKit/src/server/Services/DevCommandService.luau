--!strict

--[[
	DevCommandService

	Data reset and testing commands for Development and Test only.

	Gating, in layers:
	  * The service refuses to start at all when the environment is Production, so the
	    entry point does not exist there rather than existing and checking a flag.
	  * The entry point is a BindableFunction in ServerStorage. ServerStorage does not
	    replicate, so no client can see or reach it. It is deliberately not a remote:
	    a client-callable admin channel is exactly what the Phase 01 remote schema forbids.

	Reaching it from the Studio command bar (Server context):

	    local dev = game.ServerStorage.IceMelt.DevCommands
	    dev:Invoke("help")
	    dev:Invoke("get", player.UserId)
	    dev:Invoke("setHeat", player.UserId, 5000)
	    dev:Invoke("save", player.UserId)
	    dev:Invoke("reset", player.UserId)

	A BindableFunction is used rather than requiring this module from the command bar
	because a command-bar `require` returns a fresh module instance with its own state,
	which would not be the running service.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 10))
local DiscoveryMath = require(Shared:WaitForChild("Util", 10):WaitForChild("DiscoveryMath", 10))

local DataFolder = script.Parent.Parent:WaitForChild("Data", 10)
local ProfileSchema = require(DataFolder:WaitForChild("ProfileSchema", 10))

local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService", 10))
local AnnouncementService = require(script.Parent:WaitForChild("AnnouncementService", 10))
local ChainService = require(script.Parent:WaitForChild("ChainService", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local DiscoveryService = require(script.Parent:WaitForChild("DiscoveryService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local IceFieldService = require(script.Parent:WaitForChild("IceFieldService", 10))
local MeltService = require(script.Parent:WaitForChild("MeltService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))
local ThawService = require(script.Parent:WaitForChild("ThawService", 10))
local ToolService = require(script.Parent:WaitForChild("ToolService", 10))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService", 10))

local DevCommandService = {
	Name = "DevCommandService",
	Priority = 900,
}

local function resolvePlayer(userId: any): Player?
	if type(userId) ~= "number" then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local COMMANDS: { [string]: (...any) -> any } = {}

COMMANDS.help = function(): string
	local names = {}
	for name in COMMANDS do
		table.insert(names, name)
	end
	table.sort(names)
	return "DevCommands: " .. table.concat(names, ", ")
end

COMMANDS.backend = function(): string
	return string.format(
		"backend=%s persistent=%s environment=%s store=%s",
		DataService.getBackendName(),
		tostring(DataService.isPersistent()),
		GameConfig.Environment,
		GameConfig.DataStoreName
	)
end

--[[
	Live melt-loop counters from the running MeltService.

	Routed through this BindableFunction on purpose: a command-bar `require` of MeltService
	returns a fresh module instance whose counters are all zero, which silently produces
	nonsense in a test.
]]
COMMANDS.meltStats = function(): any
	return MeltService.getStats()
end

--[[
	The invariant that makes two players sharing one field safe: a cell can be credited to
	exactly one destroyer. damageCell returns true only on the Alive -> dead transition, so
	a second hit on an already-dead cell awards nothing.

	Worth an explicit test because it is the difference between two players cooperating and
	two players each being paid for the same ice.
]]
COMMANDS.testDoubleCredit = function(): any
	local cell = nil
	for id = 1, IceFieldService.countTotal() do
		local candidate = IceFieldService.getCell(id)
		if candidate and candidate.Alive then
			cell = candidate
			break
		end
	end

	if not cell then
		return "no alive cell available"
	end

	local overkill = cell.MaxDurability * 10
	local firstHit = IceFieldService.damageCell(cell, overkill)
	local secondHit = IceFieldService.damageCell(cell, overkill)
	local thirdHit = IceFieldService.damageCell(cell, overkill)

	return {
		CellId = cell.Id,
		FirstHitCredited = firstHit,
		SecondHitCredited = secondHit,
		ThirdHitCredited = thirdHit,
		CreditedExactlyOnce = firstHit == true and secondHit == false and thirdHit == false,
	}
end

COMMANDS.thawStats = function(): any
	return ThawService.getStats()
end

-- === Phase 07: discoveries and chains ======================================

--[[
	The normalised rarity table for a zone at a given luck.

	Reads the same function the roll uses, so what this prints is what the game will do rather
	than a second opinion about it.
]]
COMMANDS.discoveryWeights = function(zoneKey: any, luck: any): any
	if type(zoneKey) ~= "string" then
		return "usage: discoveryWeights(zoneKey, luck)"
	end
	local rows = DiscoveryMath.rarityRows(zoneKey, if type(luck) == "number" then luck else 1)

	local lines: { string } = {}
	for _, row in rows do
		table.insert(
			lines,
			string.format(
				"%-10s base %6.2f  weight %10.3f  %6.3f%%",
				row.Rarity,
				row.BaseWeight,
				row.Weight,
				row.Probability * 100
			)
		)
	end
	return {
		Zone = zoneKey,
		LuckRequested = luck,
		LuckUsed = DiscoveryMath.safeLuck(if type(luck) == "number" then luck else 1),
		Rows = lines,
	}
end

--[[
	Enumerates which discoveries each zone can produce.

	Enumeration rather than sampling: sampling can only fail to observe a violation, whereas
	walking the pools proves the "obtainable only in valid zones" criterion outright.
]]
COMMANDS.discoveryZoneMatrix = function(): any
	local result: { [string]: any } = {}
	local violations: { string } = {}

	for _, zoneKey in ContentConfig.ZoneOrder do
		local keys: { string } = {}
		for _, rarity in DiscoveryMath.zoneRarities(zoneKey) do
			for _, definition in DiscoveryMath.zoneDiscoveries(zoneKey, rarity) do
				table.insert(keys, string.format("%s(%s)", definition.Key, definition.Rarity))
				if definition.Zone ~= zoneKey then
					table.insert(
						violations,
						string.format(
							"%s is pooled in %s but belongs to %s",
							definition.Key,
							zoneKey,
							definition.Zone
						)
					)
				end
			end
		end
		table.sort(keys)
		result[zoneKey] = {
			Count = #keys,
			Rarities = DiscoveryMath.zoneRarities(zoneKey),
			Keys = keys,
		}
	end

	result.TotalInCatalogue = #ContentConfig.Discoveries
	result.Violations = if #violations == 0 then "none" else violations
	return result
end

--[[
	Samples the roll and reports the observed distribution, plus whether any sample produced a
	discovery outside the zone it was rolled in.
]]
COMMANDS.discoveryRoll = function(zoneKey: any, samples: any, luck: any): any
	if type(zoneKey) ~= "string" then
		return "usage: discoveryRoll(zoneKey, samples, luck)"
	end
	local count = if type(samples) == "number"
		then math.clamp(math.floor(samples), 1, 500000)
		else 10000
	local useLuck = if type(luck) == "number" then luck else 1

	local rng = Random.new()
	local byRarity: { [string]: number } = {}
	local byKey: { [string]: number } = {}
	local outOfZone = 0
	local nils = 0

	for _ = 1, count do
		local definition =
			DiscoveryMath.pickDiscovery(zoneKey, useLuck, rng:NextNumber(), rng:NextNumber())
		if not definition then
			nils += 1
			continue
		end
		byRarity[definition.Rarity] = (byRarity[definition.Rarity] or 0) + 1
		byKey[definition.Key] = (byKey[definition.Key] or 0) + 1
		if definition.Zone ~= zoneKey then
			outOfZone += 1
		end
	end

	local lines: { string } = {}
	for _, rarity in BalanceConfig.Discovery.RarityOrder do
		local n = byRarity[rarity]
		if n then
			table.insert(lines, string.format("%-10s %7d  %6.3f%%", rarity, n, n / count * 100))
		end
	end

	return {
		Zone = zoneKey,
		Luck = useLuck,
		Samples = count,
		Observed = lines,
		DistinctKeys = (function()
			local t = 0
			for _ in byKey do
				t += 1
			end
			return t
		end)(),
		OutOfZoneAwards = outOfZone,
		NilRolls = nils,
	}
end

--[[
	Awards a specific discovery through the real path: same profile write, same reward, same
	analytics, same announcement. Deliberately does NOT skip the zone check by inventing a
	zone — it uses the player's actual one, so a forced award cannot prove something the real
	roll could not.
]]
COMMANDS.forceDiscovery = function(userId: any, key: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(key) ~= "string" then
		return "usage: forceDiscovery(userId, discoveryKey)"
	end

	local definition = DiscoveryMath.get(key)
	if not definition then
		return string.format("unknown discovery %q", key)
	end

	local zoneKey = PlayerStateService.getCurrentZone(player)
	local stats = StatsService.get(player, zoneKey)
	if not stats then
		return "no stats for player"
	end

	local before = PlayerStateService.getDiscoveryCount(player)
	local heatBefore = PlayerStateService.getHeat(player)
	local roll = DiscoveryService.award(player, zoneKey, stats, definition)

	return {
		Awarded = roll ~= nil,
		Key = key,
		DefinitionZone = definition.Zone,
		PlayerZone = zoneKey,
		Rarity = definition.Rarity,
		IsNew = roll and roll.IsNew,
		HeatAwarded = roll and string.format("%.2f", roll.HeatAwarded),
		DistinctBefore = before,
		DistinctAfter = PlayerStateService.getDiscoveryCount(player),
		HeatDelta = string.format("%.2f", PlayerStateService.getHeat(player) - heatBefore),
	}
end

COMMANDS.clearDiscoveries = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end
	profile.Discoveries = {}
	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return { Cleared = true, DistinctNow = PlayerStateService.getDiscoveryCount(player) }
end

COMMANDS.discoveryStats = function(): any
	return DiscoveryService.getStats()
end

COMMANDS.announceStats = function(): any
	return AnnouncementService.getStats()
end

COMMANDS.analyticsCounts = function(): any
	return AnalyticsService.getCounts()
end

COMMANDS.economyLedger = function(): any
	return EconomyService.getLedger()
end

COMMANDS.chainStats = function(): any
	return ChainService.getStats()
end

--[[
	Arms a chain seed on the cell nearest the player and fires it by melting that cell, through
	the ordinary melt path. Reports the cap, what the chain actually destroyed, and whether any
	armed seed survived — which is what proves chains do not cascade.
]]
COMMANDS.testChain = function(userId: any, chainKey: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(chainKey) ~= "string" then
		return "usage: testChain(userId, chainKey)"
	end

	local definition
	for _, entry in ContentConfig.Chains do
		if entry.Key == chainKey then
			definition = entry
		end
	end
	if not definition then
		return string.format("unknown chain %q", chainKey)
	end

	local zoneKey = PlayerStateService.getCurrentZone(player)
	local stats = StatsService.get(player, zoneKey)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not stats or not root or not root:IsA("BasePart") then
		return "player has no character or stats"
	end

	local seedId = ChainService.armNearest(zoneKey, root.Position, chainKey)
	if not seedId then
		return "could not arm a seed"
	end
	local seed = IceFieldService.getCell(seedId)
	if not seed then
		return "seed vanished"
	end

	local armedBefore = IceFieldService.countArmed(zoneKey, nil)
	local before = ChainService.getStats()
	local heatBefore = PlayerStateService.getHeat(player)

	-- Fire it exactly as a melt would: destroy the seed, then hand it to the chain resolver.
	IceFieldService.damageCell(seed, seed.Durability)
	local outcome = ChainService.resolveFromSeeds(player, zoneKey, stats, { seed })

	local after = ChainService.getStats()
	local effectiveCap = math.min(definition.MaxCells, GameConfig.Limits.MaxCellsPerChainEvent)

	return {
		Chain = chainKey,
		Zone = zoneKey,
		ConfiguredMaxCells = definition.MaxCells,
		HardLimit = GameConfig.Limits.MaxCellsPerChainEvent,
		EffectiveCap = effectiveCap,
		CellsDestroyed = outcome and outcome.Credited or 0,
		WithinCap = (outcome and outcome.Credited or 0) <= effectiveCap,
		HeatAwarded = outcome and string.format("%.2f", outcome.HeatAwarded) or "0",
		HeatDelta = string.format("%.2f", PlayerStateService.getHeat(player) - heatBefore),
		CellsInBatch = outcome and #outcome.Cells or 0,
		ArmedSeedsBefore = armedBefore,
		ArmedSeedsAfter = IceFieldService.countArmed(zoneKey, nil),
		SeedsConsumedWithoutFiring = after.SeedsConsumedWithoutFiring
			- before.SeedsConsumedWithoutFiring,
	}
end

--[[
	Fires a chain twice from the same seed. The second call must award nothing: the seed is
	consumed before any cell is damaged, so there is no pending state left to replay.
]]
COMMANDS.testChainReplay = function(userId: any, chainKey: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(chainKey) ~= "string" then
		return "usage: testChainReplay(userId, chainKey)"
	end

	local zoneKey = PlayerStateService.getCurrentZone(player)
	local stats = StatsService.get(player, zoneKey)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not stats or not root or not root:IsA("BasePart") then
		return "player has no character or stats"
	end

	local seedId = ChainService.armNearest(zoneKey, root.Position, chainKey)
	local seed = seedId and IceFieldService.getCell(seedId)
	if not seed then
		return "could not arm a seed"
	end

	IceFieldService.damageCell(seed, seed.Durability)

	local heatBefore = PlayerStateService.getHeat(player)
	local first = ChainService.resolveFromSeeds(player, zoneKey, stats, { seed })
	local heatAfterFirst = PlayerStateService.getHeat(player)
	local second = ChainService.resolveFromSeeds(player, zoneKey, stats, { seed })
	local third = ChainService.resolveFromSeeds(player, zoneKey, stats, { seed })
	local heatAfterReplays = PlayerStateService.getHeat(player)

	return {
		FirstFired = first ~= nil,
		FirstCells = first and first.Credited or 0,
		FirstHeat = string.format("%.2f", heatAfterFirst - heatBefore),
		SecondFired = second ~= nil,
		ThirdFired = third ~= nil,
		HeatFromReplays = string.format("%.2f", heatAfterReplays - heatAfterFirst),
		ReplayAwardedNothing = second == nil and third == nil and math.abs(
			heatAfterReplays - heatAfterFirst
		) < 1e-9,
	}
end

--[[
	Playtest milestone timings, against the targets in docs/01.

	This is the measurement docs/03 asks for and the reason the stopwatch exists: real
	timestamps from a human run, rather than a figure derived from a formula.
]]
COMMANDS.milestones = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local marks = AnalyticsService.getMilestones(player)
	local elapsed = AnalyticsService.getRunSeconds(player)

	local TARGETS: { { Key: string, Label: string, Lo: number, Hi: number } } = {
		{ Key = "FirstUpgrade", Label = "First upgrade", Lo = 15, Hi = 30 },
		{ Key = "Tool2_Candle", Label = "Candle", Lo = 120, Hi = 240 },
		{ Key = "Zone_Cavern", Label = "Ice Cavern", Lo = 480, Hi = 720 },
		{ Key = "Thaw1", Label = "First Thaw", Lo = 1200, Hi = 1800 },
	}

	local lines: { string } = {}
	for _, t in TARGETS do
		local at = marks[t.Key]
		if at then
			local verdict = if at < t.Lo then "FAST" elseif at > t.Hi then "SLOW" else "IN WINDOW"
			table.insert(
				lines,
				string.format(
					"%-14s %7.1fs (%5.2f min)  target %.0f-%.0fs  %s",
					t.Label,
					at,
					at / 60,
					t.Lo,
					t.Hi,
					verdict
				)
			)
		else
			table.insert(
				lines,
				string.format("%-14s     not reached  target %.0f-%.0fs", t.Label, t.Lo, t.Hi)
			)
		end
	end

	-- Anything else the run recorded, such as later tools and the Frozen City.
	local extra: { string } = {}
	for name, at in marks do
		local documented = false
		for _, t in TARGETS do
			if t.Key == name then
				documented = true
				break
			end
		end
		if not documented then
			table.insert(extra, string.format("%s at %.1fs (%.2f min)", name, at, at / 60))
		end
	end
	table.sort(extra)

	return {
		RunSeconds = string.format("%.1f", elapsed),
		RunMinutes = string.format("%.2f", elapsed / 60),
		Targets = lines,
		Other = extra,
	}
end

--[[
	Wipes the profile to a true new-player state and restarts the milestone stopwatch, so a
	pacing run starts from the same place a first-time player does.
]]
COMMANDS.startCleanRun = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local reset = COMMANDS.reset(userId)

	--[[
		Zero the Heat the save yield let them earn, then start the stopwatch. The reset
		itself is now clean, but the save still yields for a moment and a player standing on
		ice keeps melting at the reset stats during it. A pacing run has to begin at exactly
		zero or the first milestone is flattered by however long the write took.
	]]
	local profile = DataService.getProfile(player)
	if profile then
		profile.Heat = 0
		profile.RunHeat = 0
		DataService.markDirty(player)
		PlayerStateService.queuePush(player)
	end

	AnalyticsService.beginRun(player)
	return {
		Reset = reset,
		Heat = profile and profile.Heat,
		RunHeat = profile and profile.RunHeat,
		Upgrades = profile and table.clone(profile.Upgrades),
		HighestTool = profile and profile.HighestTool,
		UnlockedZones = profile and table.clone(profile.UnlockedZones),
		StopwatchStarted = true,
	}
end

--[[
	Sets RunHeat directly so the Thaw threshold can be reached without playing for hours.
	Development only, and it goes through the profile rather than granting Heat, so it does
	not distort the economy ledger.
]]
COMMANDS.setRunHeat = function(userId: any, amount: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(amount) ~= "number" then
		return "amount must be a number"
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end

	profile.RunHeat = amount
	if profile.LifetimeHeat < amount then
		profile.LifetimeHeat = amount
	end
	DataService.markDirty(player)
	return { RunHeat = profile.RunHeat }
end

COMMANDS.thawPreview = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	return ThawService.preview(player)
end

COMMANDS.fieldStats = function(zoneKey: any): any
	return {
		TotalCells = IceFieldService.countTotal(),
		AliveCells = IceFieldService.countAlive(),
		ZoneAlive = if type(zoneKey) == "string" then IceFieldService.countAlive(zoneKey) else nil,
	}
end

COMMANDS.get = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end
	-- A copy, so a command-bar caller cannot mutate live data by accident.
	return {
		SchemaVersion = profile.SchemaVersion,
		Heat = profile.Heat,
		LifetimeHeat = profile.LifetimeHeat,
		RunHeat = profile.RunHeat,
		Embers = profile.Embers,
		Thaws = profile.Thaws,
		Upgrades = table.clone(profile.Upgrades),
		HighestTool = profile.HighestTool,
		EquippedTool = profile.EquippedTool,
		UnlockedZones = table.clone(profile.UnlockedZones),
		Discoveries = table.clone(profile.Discoveries),
		LoadStatus = DataService.getLoadStatus(player),
		Dirty = DataService.isDirty(player),
	}
end

COMMANDS.setHeat = function(userId: any, amount: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(amount) ~= "number" then
		return "amount must be a number"
	end

	local current = PlayerStateService.getHeat(player)
	return PlayerStateService.addHeat(player, amount - current)
end

COMMANDS.addHeat = function(userId: any, amount: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(amount) ~= "number" then
		return "amount must be a number"
	end
	return PlayerStateService.addHeat(player, amount)
end

COMMANDS.setUpgrade = function(userId: any, key: any, level: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	if type(key) ~= "string" or type(level) ~= "number" then
		return "usage: setUpgrade(userId, key, level)"
	end

	local ok = PlayerStateService.setUpgradeLevel(player, key, level)
	return {
		Ok = ok,
		Key = key,
		Level = PlayerStateService.getUpgradeLevel(player, key),
	}
end

COMMANDS.save = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end
	return DataService.save(player)
end

--[[
	Resets the profile to defaults and saves immediately, so the next load sees the reset
	rather than whatever was last written.
]]
COMMANDS.reset = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local profile = DataService.getProfile(player)
	if not profile then
		return "profile not loaded"
	end

	local defaults = ProfileSchema.default()
	for key, value in defaults do
		(profile :: any)[key] = value
	end

	--[[
		Writing the profile fields directly bypasses every mutation in PlayerStateService, so
		nothing here invalidates the stat cache or pushes the reset values onto the character.

		That is not cosmetic. DataService.save below yields inside UpdateAsync, and until the
		cache is dropped the melt loop keeps using the pre-reset damage and radius, so a
		player standing on ice earns at their old power throughout the save. A measured run
		started this way is not a clean run at all — it opens with several seconds of
		full-strength income, which is exactly the kind of silent contamination a pacing
		measurement cannot survive.
	]]
	StatsService.invalidate(player)
	UpgradeService.applyWalkSpeed(player)
	ToolService.refreshHeldModel(player)

	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return DataService.save(player)
end

--[[
	Saves, releases the session lock, and loads again: the same round trip a real leave and
	rejoin performs. This is how persistence is verified without stopping the session.
]]
COMMANDS.rejoin = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local before = PlayerStateService.getHeat(player)
	local ok, status = DataService.debugReloadProfile(player)
	local after = PlayerStateService.getHeat(player)

	return {
		Ok = ok,
		Status = status,
		HeatBefore = before,
		HeatAfter = after,
		Preserved = ok and before == after,
	}
end

--[[
	Loads from the store without saving first, so a test can control exactly what the
	loader sees. Use this rather than `rejoin` when the stored record is the thing under
	test, because `rejoin` saves over it before loading.
]]
COMMANDS.loadOnly = function(userId: any): any
	local player = resolvePlayer(userId)
	if not player then
		return "no such player in this server"
	end

	local ok, status = DataService.debugLoadFromStore(player)
	return {
		Ok = ok,
		Status = status,
		Heat = PlayerStateService.getHeat(player),
		LoadStatus = DataService.getLoadStatus(player),
	}
end

--[[
	Exercises the repair path against a deliberately corrupt profile, without touching
	anyone's real data. Returns the repair log so a test can assert on it.
]]
COMMANDS.testRepair = function(): any
	local corrupt = {
		SchemaVersion = "not a number",
		Heat = 0 / 0,
		LifetimeHeat = -50,
		Embers = math.huge,
		Thaws = 2.5,
		Upgrades = { Power = -3, Radius = "x", Crit = 999999 },
		HighestTool = 99,
		EquippedTool = 5,
		UnlockedZones = { Backyard = false, Atlantis = true },
		Discoveries = { FrozenCoin = 2, NotARealThing = 7, ToyCar = -1 },
		ReceiptHistory = "nope",
		RewardState = 12,
		Settings = nil,
	}

	local profile, log = ProfileSchema.normalise(corrupt)
	return {
		RepairCount = #log,
		Repairs = log,
		Result = {
			SchemaVersion = profile.SchemaVersion,
			Heat = profile.Heat,
			Embers = profile.Embers,
			Thaws = profile.Thaws,
			Upgrades = profile.Upgrades,
			HighestTool = profile.HighestTool,
			EquippedTool = profile.EquippedTool,
			UnlockedZones = profile.UnlockedZones,
			Discoveries = profile.Discoveries,
		},
	}
end

function DevCommandService.Start()
	if GameConfig.Environment == "Production" then
		-- Do not create the entry point at all.
		return
	end

	local root = ServerStorage:FindFirstChild(WorldConfig.RootName)
	if not root then
		root = Instance.new("Folder")
		root.Name = WorldConfig.RootName
		root.Parent = ServerStorage
	end
	assert(root ~= nil, "unreachable")

	local existing = root:FindFirstChild("DevCommands")
	if existing then
		existing:Destroy()
	end

	local entry = Instance.new("BindableFunction")
	entry.Name = "DevCommands"
	entry.Parent = root

	entry.OnInvoke = function(command: any, ...)
		if type(command) ~= "string" then
			return "first argument must be a command name"
		end

		local handler = COMMANDS[command]
		if not handler then
			return string.format("unknown command %q. %s", command, COMMANDS.help())
		end

		local ok, result = pcall(handler, ...)
		if not ok then
			return string.format("command %q errored: %s", command, tostring(result))
		end
		return result
	end
end

return DevCommandService
