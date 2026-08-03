--!strict

--[[
	AnnouncementService

	The only place in the codebase that broadcasts to every client.

	One entry point per announcement kind, for the same reason `EconomyService.trySpend` is the
	only way to charge a player: a limiter that every caller has to remember to apply is a
	limiter that will eventually be forgotten.

	What an announcement may contain, from the acceptance criterion "Legendary/Secret
	announcements reveal no sensitive data and are rate-limited":

	  * catalogue keys and the finder's display name, nothing else
	  * no UserId, no Heat, Ember, luck, upgrade or tool value
	  * no position, no counts, no free text, no numbers of any kind

	The client composes every visible string locally from ContentConfig and refuses to render a
	key it does not recognise, so the payload is a set of identifiers rather than a message.
	That makes the acceptance test a loop over the payload's keys rather than a review of every
	call site.

	Rate limiting is two buckets, consumed PLAYER FIRST and then SERVER. Order matters:
	`Validate.consumeToken` mutates on every call and has no peek, so taking the scarce global
	token first and then failing the per-player check would burn budget on an announcement that
	was never going to send.

	A dropped announcement never gates a reward. Drops are counted for diagnostics and are never
	echoed to any client — telling a client it was throttled is free tuning information for
	someone trying to farm announcements.
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
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local DiscoveryMath = require(UtilFolder:WaitForChild("DiscoveryMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))

local AnnouncementService = {
	Name = "AnnouncementService",
	Priority = 40,
}

local playerBuckets: { [Player]: Validate.TokenBucket } = {}

-- Built eagerly rather than lazily: this is one bucket for the whole server, so there is
-- nothing to defer, and an optional here would need narrowing at every use.
local serverBucket: Validate.TokenBucket = Validate.newTokenBucket(
	GameConfig.Limits.MaxAnnouncementsPerServerBurst,
	GameConfig.Limits.AnnouncementsPerServerPerSecond,
	os.clock()
)

local stats = {
	Sent = 0,
	DroppedByPlayerRate = 0,
	DroppedByServerRate = 0,
	DroppedIneligible = 0,
	DroppedInvalid = 0,
}

local function limits()
	return GameConfig.Limits
end

--[[
	Consumes the two buckets in the required order. Returns false without touching the server
	bucket when the player's own budget is exhausted.
]]
local function consumeBudget(player: Player): boolean
	local perPlayer = playerBuckets[player]
	if not perPlayer then
		perPlayer = Validate.newTokenBucket(
			limits().MaxAnnouncementsPerPlayerBurst,
			limits().AnnouncementsPerPlayerPerSecond,
			os.clock()
		)
		playerBuckets[player] = perPlayer
	end

	local now = os.clock()
	if not Validate.consumeToken(perPlayer, now) then
		stats.DroppedByPlayerRate += 1
		return false
	end

	if not Validate.consumeToken(serverBucket, now) then
		stats.DroppedByServerRate += 1
		return false
	end

	return true
end

--[[
	Builds and sends the payload. Every field is set explicitly, so a future field on some
	other type cannot leak in by being carried along in a table someone reused.
]]
local function broadcast(payload: Types.AnnouncementPayload)
	stats.Sent += 1
	RemoteRegistry.fireAllClients(RemoteNames.Name.RarityAnnouncement, payload)
end

--[[
	Announces a discovery, if it qualifies.

	Eligibility is checked here rather than by the caller so there is exactly one definition of
	"announceable". `isFirst` matters because announcing only a player's first of a kind is a
	far stronger bound than any rate limiter: the catalogue holds five announceable discoveries,
	so a single profile can produce at most five announcements in its entire lifetime.
]]
function AnnouncementService.announceDiscovery(
	player: Player,
	key: string,
	rarity: string,
	zoneKey: string,
	isFirst: boolean
): boolean
	local definition = DiscoveryMath.get(key)
	if not definition or ContentConfig.Zones[zoneKey] == nil then
		stats.DroppedInvalid += 1
		return false
	end

	if not DiscoveryMath.announces(rarity) then
		stats.DroppedIneligible += 1
		return false
	end
	if BalanceConfig.Discovery.AnnounceFirstOnly and not isFirst then
		stats.DroppedIneligible += 1
		return false
	end

	if not player.Parent then
		stats.DroppedInvalid += 1
		return false
	end
	if not consumeBudget(player) then
		return false
	end

	broadcast({
		Kind = "Discovery",
		Key = key,
		Rarity = rarity,
		ZoneKey = zoneKey,
		PlayerName = player.DisplayName,
	})
	return true
end

--[[
	Announces a chain. Only chains whose definition opts in, and only when the event was large
	enough to be worth telling the server about.
]]
function AnnouncementService.announceChain(
	player: Player,
	chainKey: string,
	zoneKey: string,
	credited: number
): boolean
	local definition: Types.ChainDefinition? = nil
	for _, entry in ContentConfig.Chains do
		if entry.Key == chainKey then
			definition = entry
			break
		end
	end

	if not definition or ContentConfig.Zones[zoneKey] == nil then
		stats.DroppedInvalid += 1
		return false
	end
	if not definition.Announce then
		stats.DroppedIneligible += 1
		return false
	end
	if not Validate.isFiniteNumber(credited) or credited < ChainConfig.MinCellsToAnnounce then
		stats.DroppedIneligible += 1
		return false
	end

	if not player.Parent then
		stats.DroppedInvalid += 1
		return false
	end
	if not consumeBudget(player) then
		return false
	end

	broadcast({
		Kind = "Chain",
		Key = chainKey,
		Rarity = nil,
		ZoneKey = zoneKey,
		PlayerName = player.DisplayName,
	})
	return true
end

function AnnouncementService.getStats()
	return {
		Sent = stats.Sent,
		DroppedByPlayerRate = stats.DroppedByPlayerRate,
		DroppedByServerRate = stats.DroppedByServerRate,
		DroppedIneligible = stats.DroppedIneligible,
		DroppedInvalid = stats.DroppedInvalid,
	}
end

function AnnouncementService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		playerBuckets[player] = nil
	end)
end

return AnnouncementService
