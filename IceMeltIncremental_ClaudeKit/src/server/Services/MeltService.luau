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
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local IceFieldService = require(script.Parent:WaitForChild("IceFieldService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))

type MeltRejectReason = Types.MeltRejectReason

local MeltService = {
	Name = "MeltService",
	Priority = 30,
}

--[[
	How far outside their zone slab a player may be and still melt in it. Generous enough
	to cover normal movement and character height, tight enough that a teleport to another
	zone is rejected.
]]
local ZONE_TOLERANCE_STUDS = 20

local buckets: { [Player]: Validate.TokenBucket } = {}
local lastSequence: { [Player]: number } = {}

-- Diagnostics for the development overlay. Server-side counters only.
local stats = {
	Accepted = 0,
	Rejected = 0,
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
	Which zone the player is actually standing in, from their server-side position.
	Returns nil when they are not inside any zone, which rejects the pulse.
]]
local function resolveZone(position: Vector3): string?
	for _, zoneKey in ContentConfig.ZoneOrder do
		local layout = WorldConfig.Zones[zoneKey]
		if layout then
			local halfX = layout.GroundSize.X / 2 + ZONE_TOLERANCE_STUDS
			local halfZ = layout.GroundSize.Z / 2 + ZONE_TOLERANCE_STUDS
			local delta = position - layout.Center
			if math.abs(delta.X) <= halfX and math.abs(delta.Z) <= halfZ then
				return zoneKey
			end
		end
	end
	return nil
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

	local zoneKey = resolveZone(position)
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

	local profile = DataService.getProfile(player)
	if not profile then
		reject(player, "NoProfile")
		return
	end

	local meltStats = StatMath.computeMeltStats(profile.Upgrades, profile.EquippedTool, zoneKey)

	local cells = IceFieldService.queryCells(
		zoneKey,
		position,
		meltStats.Radius,
		GameConfig.Limits.MaxCellsPerPulse
	)

	if #cells == 0 then
		-- Nothing in range is a normal outcome, not an error. Reply with an empty batch so
		-- the client can stop predicting.
		RemoteRegistry.fireClient(RemoteNames.Name.MeltResult, player, {
			Sequence = sequence,
			ZoneKey = zoneKey,
			Cells = {},
			HeatGranted = 0,
		})
		return
	end

	local results: { Types.MeltCellResult } = {}
	local totalHeat = 0
	local destroyed = 0

	for _, cell in cells do
		-- Crits multiply the reward, not the damage. Scaling damage as well would make
		-- Crit a second Power stat and double-dip against the balance curve.
		local critical = math.random() < meltStats.CritChance
		local damage = meltStats.Damage

		local wasDestroyed = IceFieldService.damageCell(cell, damage)

		if wasDestroyed then
			destroyed += 1
			totalHeat += StatMath.heatForCell(meltStats, zoneKey, critical)
		end

		table.insert(results, {
			CellId = cell.Id,
			Damage = damage,
			Destroyed = wasDestroyed,
			Critical = critical and wasDestroyed,
		})
	end

	-- Final ceiling on the reward, after every multiplier.
	totalHeat = Validate.clampFinite(totalHeat, 0, BalanceConfig.Melt.MaxHeatPerPulse)

	if totalHeat > 0 then
		-- The only path by which Heat ever changes.
		PlayerStateService.addHeat(player, totalHeat)
	end

	stats.Accepted += 1
	stats.CellsDestroyed += destroyed
	stats.HeatGranted += totalHeat

	-- One remote for the whole pulse, carrying every cell touched.
	RemoteRegistry.fireClient(RemoteNames.Name.MeltResult, player, {
		Sequence = sequence,
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
		Rejected = stats.Rejected,
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
end

return MeltService
