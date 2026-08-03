--!strict

--[[
	PlayerStateService

	The only gateway to player state for the rest of the server, and the only thing that
	replicates state to clients.

	Two rules it enforces:

	1. No mutable profile table ever leaves this module. Getters return primitives or
	   copies, so a caller cannot hold a reference and mutate a player's saved data from
	   somewhere else. Mutations are explicit, named, validated, and clamped.

	2. Clients receive a ReplicatedPlayerState and nothing else. ReceiptHistory,
	   LifetimeHeat, RunHeat, RewardState, and every anti-exploit counter stay server-side
	   by construction rather than by remembering to strip them.

	Replication is throttled: a burst of mutations produces one snapshot on the next tick
	instead of one remote per change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))

type PlayerProfile = Types.PlayerProfile
type ReplicatedPlayerState = Types.ReplicatedPlayerState

local PlayerStateService = {
	Name = "PlayerStateService",
	-- After DataService, before anything that reads state.
	Priority = 10,
}

local REPLICATION_INTERVAL = 0.1

local readyPlayers: { [Player]: boolean } = {}
local readyBuckets: { [Player]: Validate.TokenBucket } = {}
local pendingPush: { [Player]: boolean } = {}

--[[
	Which zone the server believes each player is in. Lives here rather than in ZoneService
	because the snapshot needs it and ZoneService already depends on this module; putting it
	the other way round would be a circular require. ZoneService remains the only writer.
]]
local currentZone: { [Player]: string } = {}

function PlayerStateService.setCurrentZone(player: Player, zoneKey: string)
	currentZone[player] = zoneKey
end

function PlayerStateService.getCurrentZone(player: Player): string
	return currentZone[player] or ContentConfig.StartingZone
end

-- === Snapshot ==============================================================

local function countDiscoveries(profile: PlayerProfile): number
	local total = 0
	for _ in profile.Discoveries do
		total += 1
	end
	return total
end

--[[
	Builds the client-facing view. This is an allow-list: every field is named explicitly,
	so adding a field to the profile cannot accidentally start replicating it.
]]
local function buildSnapshot(player: Player, profile: PlayerProfile): ReplicatedPlayerState
	return {
		Heat = profile.Heat,
		Embers = profile.Embers,
		Thaws = profile.Thaws,
		Upgrades = table.clone(profile.Upgrades),
		HighestTool = profile.HighestTool,
		EquippedTool = profile.EquippedTool,
		UnlockedZones = table.clone(profile.UnlockedZones),
		DiscoveryCount = countDiscoveries(profile),
		-- Finished numbers, not inputs. The client shows what the server decided rather
		-- than recomputing the balance curves itself. Stats are zone-dependent, so they are
		-- resolved for the zone the player is actually standing in.
		Stats = StatsService.getForDisplay(player, PlayerStateService.getCurrentZone(player)),
		CurrentZone = PlayerStateService.getCurrentZone(player),
	}
end

function PlayerStateService.getSnapshot(player: Player): ReplicatedPlayerState?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	return buildSnapshot(player, profile)
end

function PlayerStateService.isReady(player: Player): boolean
	return DataService.isLoaded(player) and readyPlayers[player] == true
end

--[[
	Queues a replication. Coalesced, so twenty mutations in one frame send one snapshot.
]]
function PlayerStateService.queuePush(player: Player)
	if DataService.isLoaded(player) then
		pendingPush[player] = true
	end
end

function PlayerStateService.push(player: Player)
	local snapshot = PlayerStateService.getSnapshot(player)
	if not snapshot then
		return
	end
	pendingPush[player] = nil
	RemoteRegistry.fireClient(RemoteNames.Name.PlayerState, player, snapshot)
end

-- === Getters ===============================================================
-- Primitives and copies only. Nothing here hands out a live table.

function PlayerStateService.getHeat(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then profile.Heat else 0
end

function PlayerStateService.getEmbers(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then profile.Embers else 0
end

function PlayerStateService.getUpgradeLevel(player: Player, key: string): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	return (profile.Upgrades :: any)[key] or 0
end

function PlayerStateService.getEquippedTool(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then profile.EquippedTool else ContentConfig.StartingToolIndex
end

function PlayerStateService.getHighestTool(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then profile.HighestTool else ContentConfig.StartingToolIndex
end

function PlayerStateService.isZoneUnlocked(player: Player, zoneKey: string): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	return profile.UnlockedZones[zoneKey] == true
end

function PlayerStateService.getDiscoveryCount(player: Player): number
	local profile = DataService.getProfile(player)
	return if profile then countDiscoveries(profile) else 0
end

-- === Mutations =============================================================
-- Each one validates, clamps, marks the profile dirty, and queues replication.

--[[
	Marks the profile dirty, drops any cached stat block, and queues a replication.

	Stat invalidation belongs here rather than in the callers. It used to live only in
	UpgradeService.purchase, so every other route into these mutations — dev commands, a
	Thaw, and anything a later phase adds — left StatsService serving the stat block from
	before the change. The player kept their old damage and radius until something unrelated
	happened to invalidate the cache.

	Calling it on every mutation is cheap: the next read recomputes, and these mutations are
	rare compared to the melt pulses that read the cache.
]]
local function commit(player: Player)
	DataService.markDirty(player)
	StatsService.invalidate(player)
	PlayerStateService.queuePush(player)
end

--[[
	Adds (or removes, with a negative amount) Heat. Returns the new balance.
	Heat is clamped into [0, MaxHeat]: a negative balance or a NaN would poison every
	downstream cost check.
]]
function PlayerStateService.addHeat(player: Player, amount: number): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	if not Validate.isFiniteNumber(amount) then
		warn(
			string.format("[IceMelt] addHeat got a non-finite amount for %s; ignored", player.Name)
		)
		return profile.Heat
	end

	profile.Heat = Validate.clampFinite(profile.Heat + amount, 0, GameConfig.Limits.MaxHeat)

	if amount > 0 then
		profile.LifetimeHeat = Validate.clampFinite(profile.LifetimeHeat + amount, 0, math.huge - 1)
		profile.RunHeat = Validate.clampFinite(profile.RunHeat + amount, 0, math.huge - 1)
	end

	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return profile.Heat
end

function PlayerStateService.addEmbers(player: Player, amount: number): number
	local profile = DataService.getProfile(player)
	if not profile then
		return 0
	end
	if not Validate.isFiniteNumber(amount) then
		return profile.Embers
	end

	profile.Embers = Validate.clampFinite(profile.Embers + amount, 0, GameConfig.Limits.MaxEmbers)
	-- Embers feed the permanent Heat multiplier, so the cached stat block is now stale.
	commit(player)
	return profile.Embers
end

--[[
	Sets an upgrade level. Rejects unknown keys and anything past the configured cap, so a
	bug in a caller cannot write a level the balance curve never intended.
]]
function PlayerStateService.setUpgradeLevel(player: Player, key: string, level: number): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end

	local definition = BalanceConfig.Upgrades[key]
	if not definition then
		warn(string.format("[IceMelt] setUpgradeLevel got unknown upgrade %q", tostring(key)))
		return false
	end
	if not Validate.isIntegerInRange(level, 0, definition.Cap) then
		return false
	end

	(profile.Upgrades :: any)[key] = level
	commit(player)
	return true
end

--[[
	Raises the highest unlocked tool. Never lowers it: a tool once bought stays bought.
]]
function PlayerStateService.setHighestTool(player: Player, index: number): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if not Validate.isIntegerInRange(index, 1, #ContentConfig.Tools) then
		return false
	end
	if index <= profile.HighestTool then
		return false
	end

	profile.HighestTool = index
	commit(player)
	return true
end

--[[
	Equips a tool the player has actually unlocked. The unlock check lives here rather
	than in the caller so every path is covered.
]]
function PlayerStateService.setEquippedTool(player: Player, index: number): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if not Validate.isIntegerInRange(index, 1, #ContentConfig.Tools) then
		return false
	end
	if index > profile.HighestTool then
		return false
	end

	profile.EquippedTool = index
	commit(player)
	return true
end

function PlayerStateService.unlockZone(player: Player, zoneKey: string): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if ContentConfig.Zones[zoneKey] == nil then
		warn(string.format("[IceMelt] unlockZone got unknown zone %q", tostring(zoneKey)))
		return false
	end
	if profile.UnlockedZones[zoneKey] then
		return false
	end

	profile.UnlockedZones[zoneKey] = true
	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return true
end

--[[
	Records a discovery. Returns true when it was the player's first of that kind, which
	is what the reveal UI needs to know.
]]
function PlayerStateService.addDiscovery(player: Player, key: string): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end

	local known = false
	for _, discovery in ContentConfig.Discoveries do
		if discovery.Key == key then
			known = true
			break
		end
	end
	if not known then
		warn(string.format("[IceMelt] addDiscovery got unknown discovery %q", tostring(key)))
		return false
	end

	local previous = profile.Discoveries[key] or 0
	profile.Discoveries[key] = previous + 1

	DataService.markDirty(player)
	PlayerStateService.queuePush(player)
	return previous == 0
end

--[[
	Applies a Thaw reset.

	The reset and retain lists come straight from docs/03 and are written out field by field
	rather than by clearing and re-adding, so a future profile field is retained by default.
	Silently wiping something new because a reset function was too clever is how prestige
	systems destroy player progress.

	    Reset:  Heat, RunHeat, all seven upgrade levels, tools back to the starting tool,
	            zones back to the starting zone
	    Retain: Embers, Thaws, LifetimeHeat, Discoveries, RewardState, Settings,
	            ReceiptHistory, SchemaVersion

	LifetimeHeat is deliberately retained: it is a lifetime counter, and resetting it would
	make it a run counter under a misleading name.
]]
function PlayerStateService.applyThawReset(player: Player, emberAward: number): boolean
	local profile = DataService.getProfile(player)
	if not profile then
		return false
	end
	if not Validate.isIntegerInRange(emberAward, 0, GameConfig.Limits.MaxEmbers) then
		return false
	end

	profile.Embers =
		Validate.clampFinite(profile.Embers + emberAward, 0, GameConfig.Limits.MaxEmbers)
	profile.Thaws += 1

	profile.Heat = 0
	profile.RunHeat = 0

	for _, key in BalanceConfig.UpgradeOrder do
		(profile.Upgrades :: any)[key] = 0
	end

	profile.HighestTool = ContentConfig.StartingToolIndex
	profile.EquippedTool = ContentConfig.StartingToolIndex

	local zones: { [string]: boolean } = {}
	zones[ContentConfig.StartingZone] = true
	profile.UnlockedZones = zones

	commit(player)
	return true
end

-- === Handshake =============================================================

local function onClientReady(player: Player)
	--[[
		The bucket is created on PlayerAdded, which is wired in Start, but this handler is
		wired in Init. A handshake that arrives in that window found no bucket and was
		dropped, silently spending one of the client's four retries. Create it on demand
		instead, so the window cannot cost a player their state.
	]]
	local bucket = readyBuckets[player]
	if not bucket then
		bucket = Validate.newTokenBucket(3, 0.5, os.clock())
		readyBuckets[player] = bucket
	end

	if not Validate.consumeToken(bucket, os.clock()) then
		return
	end

	readyPlayers[player] = true

	-- The client may finish starting before its profile has loaded. Say nothing now; the
	-- DataService loaded signal pushes the first snapshot when it is genuinely ready.
	if DataService.isLoaded(player) then
		PlayerStateService.push(player)
	end
end

local function onPlayerAdded(player: Player)
	readyBuckets[player] = Validate.newTokenBucket(3, 0.5, os.clock())
end

local function onPlayerRemoving(player: Player)
	readyPlayers[player] = nil
	readyBuckets[player] = nil
	pendingPush[player] = nil
	currentZone[player] = nil
end

function PlayerStateService.Init()
	RemoteRegistry.connect(RemoteNames.Name.ClientReady, onClientReady)
end

function PlayerStateService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		if not readyBuckets[player] then
			onPlayerAdded(player)
		end
	end

	-- Push the first snapshot as soon as the profile exists, for players whose handshake
	-- landed before their load finished.
	DataService.getLoadedSignal():Connect(function(player: Player)
		if readyPlayers[player] then
			PlayerStateService.push(player)
		end
	end)

	-- Coalesced replication.
	task.spawn(function()
		while true do
			task.wait(REPLICATION_INTERVAL)
			for player in pendingPush do
				if player.Parent then
					PlayerStateService.push(player)
				else
					pendingPush[player] = nil
				end
			end
		end
	end)
end

return PlayerStateService
