--!strict

--[[
	ZoneService

	Zone unlock purchases, travel, and the authority on which zone a player is in.

	"Locked travel cannot be forced by client remotes or teleporting character state alone"
	needs two independent guards, because they fail differently:

	  1. The travel remote validates ownership before moving anyone. A client asking to
	     travel to a locked zone is refused.
	  2. A patrol checks where players actually are. An exploiter who moves their own
	     character by other means is standing in a locked zone without ever asking, so the
	     remote guard never sees them. The patrol returns them to their best unlocked zone.

	MeltService independently derives the zone from the player's position and refuses to
	award Heat outside an unlocked zone, so even during the window before the patrol fires,
	being somewhere illegal earns nothing.

	Zone membership is derived from position, never from a client claim. Travel sets the
	position; it does not set a "current zone" the server then trusts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))

local ZoneService = {
	Name = "ZoneService",
	Priority = 50,
}

--[[
	Matches the tolerance MeltService uses, so the two agree on where a zone ends. If these
	drifted apart a player could be meltable-in-zone by one module and out-of-zone by the
	other.
]]
local ZONE_TOLERANCE_STUDS = 20
local PATROL_INTERVAL = 1

local buckets: { [Player]: Validate.TokenBucket } = {}
local enforcementCount = 0

local function respond(player: Player, action: string, status: string, reason: string?)
	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = action,
		Status = status,
		Reason = reason,
	})
end

--[[
	Which zone a world position falls in, or nil if none. The single definition of zone
	membership; everything else asks this.
]]
function ZoneService.zoneAt(position: Vector3): string?
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

function ZoneService.getCurrentZone(player: Player): string
	return PlayerStateService.getCurrentZone(player)
end

--[[
	The furthest zone the player owns, used as the destination when returning someone from
	somewhere they should not be.
]]
local function bestUnlockedZone(player: Player): string
	local best = ContentConfig.StartingZone
	for _, zoneKey in ContentConfig.ZoneOrder do
		if PlayerStateService.isZoneUnlocked(player, zoneKey) then
			best = zoneKey
		end
	end
	return best
end

local function placeCharacter(player: Player, zoneKey: string): boolean
	local layout = WorldConfig.Zones[zoneKey]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not layout or not root or not root:IsA("BasePart") then
		return false
	end

	root.CFrame = CFrame.new(layout.ArrivalPosition, layout.ArrivalPosition + Vector3.new(0, 0, 1))

	PlayerStateService.setCurrentZone(player, zoneKey)
	-- Radius and luck are zone-dependent, so the cached stat block is now stale.
	StatsService.invalidate(player)
	PlayerStateService.queuePush(player)
	return true
end

-- === Unlock and travel =====================================================

function ZoneService.unlock(player: Player, zoneKey: string): (boolean, string?)
	if not DataService.isLoaded(player) then
		return false, "NoProfile"
	end

	local definition = ContentConfig.Zones[zoneKey]
	if not definition then
		return false, "UnknownZone"
	end
	if PlayerStateService.isZoneUnlocked(player, zoneKey) then
		return false, "AlreadyUnlocked"
	end

	--[[
		Zones unlock in order. Without this a player could buy Frozen City while still on
		the Backyard, skipping the Cavern entirely and landing somewhere the balance curve
		never intended them to be.
	]]
	local previousKey: string? = nil
	for index, key in ContentConfig.ZoneOrder do
		if key == zoneKey then
			previousKey = if index > 1 then ContentConfig.ZoneOrder[index - 1] else nil
			break
		end
	end
	if previousKey and not PlayerStateService.isZoneUnlocked(player, previousKey) then
		return false, "PreviousZoneLocked"
	end

	if not EconomyService.trySpend(player, definition.Cost, "ZoneUnlock") then
		return false, "Insufficient"
	end

	if not PlayerStateService.unlockZone(player, zoneKey) then
		EconomyService.grant(player, definition.Cost, "ZoneRefund")
		warn(
			string.format("[IceMelt] ZoneService: unlockZone failed for %s; refunded", player.Name)
		)
		return false, "Failed"
	end

	--[[
		Travel there immediately: the player just paid to go, so making them press a second
		button would be pointless friction.

		A failure here is not a failed purchase. The zone is unlocked and saved either way,
		and the player can travel from the Zones panel; the only cause is having no live
		character to move. Warn rather than fail the unlock, which would imply the Heat was
		not spent.
	]]
	-- Playtest stopwatch. The Cavern is the documented 8-12 minute target.
	AnalyticsService.markMilestone(player, "Zone_" .. zoneKey)

	if not placeCharacter(player, zoneKey) then
		warn(
			string.format(
				"[IceMelt] ZoneService: unlocked %s for %s but could not move them (no character). "
					.. "The zone is unlocked; they can travel manually.",
				zoneKey,
				player.Name
			)
		)
	end
	return true, nil
end

function ZoneService.travel(player: Player, zoneKey: string): (boolean, string?)
	if not DataService.isLoaded(player) then
		return false, "NoProfile"
	end
	if ContentConfig.Zones[zoneKey] == nil then
		return false, "UnknownZone"
	end
	if not PlayerStateService.isZoneUnlocked(player, zoneKey) then
		return false, "ZoneLocked"
	end
	if not placeCharacter(player, zoneKey) then
		return false, "NoCharacter"
	end
	return true, nil
end

-- === Remote handlers =======================================================

local function consume(player: Player): boolean
	local bucket = buckets[player]
	return bucket ~= nil and Validate.consumeToken(bucket, os.clock())
end

local function readZoneKey(payload: any): string?
	if type(payload) ~= "table" then
		return nil
	end
	local key = (payload :: any).ZoneKey
	if not Validate.isNonEmptyString(key, 32) then
		return nil
	end
	return key
end

local function onUnlockZone(player: Player, payload: any)
	if not consume(player) then
		respond(player, "UnlockZone", "Denied", "RateLimited")
		return
	end

	local zoneKey = readZoneKey(payload)
	if not zoneKey then
		respond(player, "UnlockZone", "Denied", "InvalidPayload")
		return
	end

	local ok, reason = ZoneService.unlock(player, zoneKey)
	respond(player, "UnlockZone", if ok then "Ok" else "Denied", reason)
end

local function onTravelZone(player: Player, payload: any)
	if not consume(player) then
		respond(player, "TravelZone", "Denied", "RateLimited")
		return
	end

	local zoneKey = readZoneKey(payload)
	if not zoneKey then
		respond(player, "TravelZone", "Denied", "InvalidPayload")
		return
	end

	local ok, reason = ZoneService.travel(player, zoneKey)
	respond(player, "TravelZone", if ok then "Ok" else "Denied", reason)
end

-- === Patrol ================================================================

--[[
	Keeps tracked zone membership honest, and returns anyone standing somewhere they do not
	own.

	This is the guard the travel remote cannot provide: an exploiter who moves their own
	character never sends a request, so only observing actual positions catches them.
]]
-- Variadic return type so `local ok, err = pcall(patrol)` has a second value to bind.
local function patrol(): ...any
	for _, player in Players:GetPlayers() do
		if not DataService.isLoaded(player) then
			continue
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local zoneKey = ZoneService.zoneAt(root.Position)

		if zoneKey and not PlayerStateService.isZoneUnlocked(player, zoneKey) then
			local destination = bestUnlockedZone(player)
			enforcementCount += 1
			warn(
				string.format(
					"[IceMelt] ZoneService: %s was in locked zone %s; returned to %s",
					player.Name,
					zoneKey,
					destination
				)
			)
			placeCharacter(player, destination)
			respond(player, "TravelZone", "Denied", "ZoneLocked")
			continue
		end

		if zoneKey and PlayerStateService.getCurrentZone(player) ~= zoneKey then
			PlayerStateService.setCurrentZone(player, zoneKey)
			-- Zone affects luck and heat, so the cached stats must be recomputed.
			StatsService.invalidate(player)
			PlayerStateService.queuePush(player)
		end
	end
end

function ZoneService.getEnforcementCount(): number
	return enforcementCount
end

-- === Lifecycle =============================================================

local function onPlayerAdded(player: Player)
	buckets[player] = Validate.newTokenBucket(8, 4, os.clock())
	PlayerStateService.setCurrentZone(player, ContentConfig.StartingZone)
end

function ZoneService.Init()
	RemoteRegistry.connect(RemoteNames.Name.UnlockZone, onUnlockZone)
	RemoteRegistry.connect(RemoteNames.Name.TravelZone, onTravelZone)
end

function ZoneService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		if not buckets[player] then
			onPlayerAdded(player)
		end
	end

	-- One patrol loop for every player, rather than a connection per character.
	task.spawn(function()
		while true do
			task.wait(PATROL_INTERVAL)
			local ok, err = pcall(patrol)
			if not ok then
				warn(string.format("[IceMelt] ZoneService: patrol errored: %s", tostring(err)))
			end
		end
	end)
end

return ZoneService
