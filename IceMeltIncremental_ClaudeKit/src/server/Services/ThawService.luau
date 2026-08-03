--!strict

--[[
	ThawService

	The single prestige layer: bank a run's Heat for permanent Embers.

	Two-step by design. `RequestThaw` returns a preview and an intent token; `ConfirmThaw`
	spends that token. A one-shot reset remote would let a mis-tap wipe a run, and a preview
	the player never sees would make the confirmation dialogue a lie.

	How duplicate Embers are prevented, which is the acceptance criterion:

	  * The token is a single-use nonce. It is cleared before any state changes, so even a
	    confirmation that arrives twice in the same frame finds nothing to spend the second
	    time.
	  * The award is recomputed at confirmation time from live state. The token carries
	    intent, not a promised amount, so a stale token cannot lock in a payout from a
	    richer moment.
	  * Eligibility is re-checked at confirmation. A player who somehow spent their RunHeat
	    between preview and confirm is refused rather than paid for Heat they no longer have.

	The token is also invalidated whenever the profile reloads, so a token captured before a
	rejoin is worthless afterwards.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Types = require(Shared:WaitForChild("Types", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local AnalyticsService = require(script.Parent:WaitForChild("AnalyticsService", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))
local ZoneService = require(script.Parent:WaitForChild("ZoneService", 10))

type ThawPreview = Types.ThawPreview

local ThawService = {
	Name = "ThawService",
	Priority = 55,
}

-- A token older than this is refused, so an abandoned dialogue cannot be confirmed an hour
-- later against a run that has moved on.
local TOKEN_LIFETIME_SECONDS = 120

type PendingToken = {
	Token: string,
	IssuedAt: number,
}

local pending: { [Player]: PendingToken? } = {}
local buckets: { [Player]: Validate.TokenBucket } = {}
local thawCount = 0
local duplicateAttempts = 0

local function respond(player: Player, action: string, status: string, reason: string?)
	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = action,
		Status = status,
		Reason = reason,
	})
end

--[[
	What a Thaw would do right now. Pure: computes from live state and changes nothing, so
	the client can call it freely to keep a dialogue current.
]]
function ThawService.preview(player: Player): ThawPreview
	local profile = DataService.getProfile(player)
	local required = BalanceConfig.Thaw.BaseRequirement

	if not profile then
		return {
			Eligible = false,
			RunHeat = 0,
			Required = required,
			EmberAward = 0,
			CurrentEmbers = 0,
			CurrentMultiplier = 1,
			ProjectedMultiplier = 1,
			Token = nil,
		}
	end

	local award = StatMath.emberAward(profile.RunHeat)

	return {
		Eligible = award > 0,
		RunHeat = profile.RunHeat,
		Required = required,
		EmberAward = award,
		CurrentEmbers = profile.Embers,
		CurrentMultiplier = StatMath.emberMultiplier(profile.Embers),
		ProjectedMultiplier = StatMath.emberMultiplier(profile.Embers + award),
		Token = nil,
	}
end

function ThawService.invalidateToken(player: Player)
	pending[player] = nil
end

--[[
	Issues an intent token alongside the preview. Issuing a second token invalidates the
	first, so only the most recent dialogue can be confirmed.
]]
local function issueToken(player: Player): string
	local token = HttpService:GenerateGUID(false)
	pending[player] = { Token = token, IssuedAt = os.clock() }
	return token
end

--[[
	Performs the Thaw. Returns the Embers awarded, or nil with a reason.
]]
function ThawService.confirm(player: Player, token: any): (number?, string?)
	if not DataService.isLoaded(player) then
		return nil, "NoProfile"
	end
	if not Validate.isNonEmptyString(token, 64) then
		return nil, "InvalidPayload"
	end

	local entry = pending[player]
	if not entry then
		-- Either never requested, or already spent. Both are the same to the caller, and
		-- counting it separately makes a replay attempt visible in the logs.
		duplicateAttempts += 1
		return nil, "NoPendingThaw"
	end
	if entry.Token ~= token then
		duplicateAttempts += 1
		return nil, "StaleToken"
	end
	if os.clock() - entry.IssuedAt > TOKEN_LIFETIME_SECONDS then
		pending[player] = nil
		return nil, "TokenExpired"
	end

	-- Spend the token before anything else changes. A second confirmation arriving while
	-- this one is still running finds nothing pending and is refused.
	pending[player] = nil

	local profile = DataService.getProfile(player)
	if not profile then
		return nil, "NoProfile"
	end

	-- Recomputed from live state, never taken from the preview.
	local award = StatMath.emberAward(profile.RunHeat)
	if award <= 0 then
		return nil, "NotEligible"
	end

	local runHeatBanked = profile.RunHeat
	local thawNumber = profile.Thaws + 1

	if not PlayerStateService.applyThawReset(player, award) then
		return nil, "Failed"
	end

	StatsService.invalidate(player)

	-- The reset revoked every zone beyond the Backyard, so a player standing in the Cavern
	-- is now trespassing in their own save. Move them before the ZoneService patrol does it
	-- for them and reports it as an enforcement.
	ZoneService.travel(player, ContentConfig.StartingZone)

	-- Persist immediately. A Thaw is the single most painful thing to lose to a crash,
	-- because the run is already gone.
	DataService.save(player)

	thawCount += 1
	AnalyticsService.logEvent(player, "ThawCompleted", {
		ThawNumber = thawNumber,
		EmberAward = award,
		RunHeatBanked = math.floor(runHeatBanked),
		TotalEmbers = profile.Embers,
	})
	if thawNumber == 1 then
		AnalyticsService.logEvent(player, "FirstThawCompleted", { EmberAward = award })
	end

	return award, nil
end

function ThawService.getStats()
	return {
		ThawCount = thawCount,
		DuplicateAttempts = duplicateAttempts,
		PendingTokens = (function()
			local total = 0
			for _ in pending do
				total += 1
			end
			return total
		end)(),
	}
end

-- === Remote handlers =======================================================

local function consume(player: Player): boolean
	local bucket = buckets[player]
	return bucket ~= nil and Validate.consumeToken(bucket, os.clock())
end

local function onRequestThaw(player: Player)
	if not consume(player) then
		respond(player, "RequestThaw", "Denied", "RateLimited")
		return
	end
	if not DataService.isLoaded(player) then
		respond(player, "RequestThaw", "Denied", "NoProfile")
		return
	end

	local preview = ThawService.preview(player)
	AnalyticsService.logEvent(player, "ThawScreenOpened", { Eligible = preview.Eligible })

	if preview.Eligible then
		preview.Token = issueToken(player)
	end

	-- The preview rides back on ActionResult rather than needing its own remote, keeping
	-- the schema closed.
	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = "RequestThaw",
		Status = "Ok",
		Reason = nil,
		Preview = preview,
	})
end

local function onConfirmThaw(player: Player, payload: any)
	if not consume(player) then
		respond(player, "ConfirmThaw", "Denied", "RateLimited")
		return
	end
	if type(payload) ~= "table" then
		respond(player, "ConfirmThaw", "Denied", "InvalidPayload")
		return
	end

	local award, reason = ThawService.confirm(player, (payload :: any).Token)
	if not award then
		respond(player, "ConfirmThaw", "Denied", reason)
		return
	end

	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = "ConfirmThaw",
		Status = "Ok",
		Reason = nil,
		EmberAward = award,
	})
end

-- === Lifecycle =============================================================

local function onPlayerAdded(player: Player)
	buckets[player] = Validate.newTokenBucket(6, 3, os.clock())
	pending[player] = nil
end

function ThawService.Init()
	RemoteRegistry.connect(RemoteNames.Name.RequestThaw, onRequestThaw)
	RemoteRegistry.connect(RemoteNames.Name.ConfirmThaw, onConfirmThaw)
end

function ThawService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		pending[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		if not buckets[player] then
			onPlayerAdded(player)
		end
	end

	-- A token captured before a rejoin must not survive it: the profile it described is
	-- gone and a fresh load may have different RunHeat.
	DataService.getLoadedSignal():Connect(function(player: Player)
		pending[player] = nil
	end)
end

return ThawService
