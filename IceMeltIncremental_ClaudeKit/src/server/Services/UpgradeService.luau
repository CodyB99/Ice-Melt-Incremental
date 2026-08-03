--!strict

--[[
	UpgradeService

	Handles PurchaseUpgrade. One level per request.

	The client sends an upgrade key and nothing else. It cannot send a cost, a level, or a
	quantity, so there is no number in the message to tamper with: the server reads the
	current level from the profile, derives the cost from shared configuration, and charges
	that. "Client cannot buy free or negative upgrades" is therefore structural rather than
	a check that could be forgotten.

	Requests are rate limited per player. Without it a client could fire thousands of
	purchase attempts a second; each one is cheap, but thousands are not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 10))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))

local UpgradeService = {
	Name = "UpgradeService",
	Priority = 40,
}

local buckets: { [Player]: Validate.TokenBucket } = {}

local function respond(player: Player, status: string, reason: string?)
	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = "PurchaseUpgrade",
		Status = status,
		Reason = reason,
	})
end

--[[
	Buys exactly one level. Returns the new level, or nil with a reason.

	Also exposed for dev commands and later phases, so the validation cannot be bypassed by
	calling a different entry point.
]]
function UpgradeService.purchase(player: Player, key: string): (number?, string?)
	if not DataService.isLoaded(player) then
		return nil, "NoProfile"
	end

	local definition = BalanceConfig.Upgrades[key]
	if not definition then
		return nil, "UnknownUpgrade"
	end

	local level = PlayerStateService.getUpgradeLevel(player, key)
	if level >= definition.Cap then
		return nil, "AtCap"
	end

	-- Cost comes from shared configuration and the server's own level reading.
	local cost = StatMath.upgradeCost(key, level)
	if cost == nil then
		return nil, "AtCap"
	end

	if not EconomyService.trySpend(player, cost, "UpgradePurchase") then
		return nil, "Insufficient"
	end

	if not PlayerStateService.setUpgradeLevel(player, key, level + 1) then
		-- Refund rather than silently pocketing the Heat. Reaching here means a bug, but a
		-- bug that charges a player and gives nothing is the worst kind.
		EconomyService.grant(player, cost, "UpgradeRefund")
		warn(
			string.format(
				"[IceMelt] UpgradeService: setUpgradeLevel failed for %s %s; refunded",
				player.Name,
				key
			)
		)
		return nil, "Failed"
	end

	StatsService.invalidate(player)
	UpgradeService.applyWalkSpeed(player)

	return level + 1, nil
end

--[[
	Walk speed is a stat, so it is pushed to the character whenever it can change.
]]
function UpgradeService.applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local stats = StatsService.get(player, ContentConfig.StartingZone)
	if stats then
		humanoid.WalkSpeed = stats.WalkSpeed
	end
end

local function onPurchaseUpgrade(player: Player, payload: any)
	local bucket = buckets[player]
	if not bucket or not Validate.consumeToken(bucket, os.clock()) then
		respond(player, "Denied", "RateLimited")
		return
	end

	if type(payload) ~= "table" then
		respond(player, "Denied", "InvalidPayload")
		return
	end

	local key = (payload :: any).Key
	if not Validate.isNonEmptyString(key, 32) then
		respond(player, "Denied", "InvalidPayload")
		return
	end

	local newLevel, reason = UpgradeService.purchase(player, key)
	if not newLevel then
		respond(player, "Denied", reason)
		return
	end

	respond(player, "Ok", nil)
end

local function onPlayerAdded(player: Player)
	-- Generous for a human tapping a button, restrictive for a script.
	buckets[player] = Validate.newTokenBucket(10, 5, os.clock())
end

local function onPlayerRemoving(player: Player)
	buckets[player] = nil
end

function UpgradeService.Init()
	RemoteRegistry.connect(RemoteNames.Name.PurchaseUpgrade, onPurchaseUpgrade)
end

function UpgradeService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in Players:GetPlayers() do
		if not buckets[player] then
			onPlayerAdded(player)
		end
	end

	-- Reapply walk speed on every spawn, from authoritative state.
	Players.PlayerAdded:Connect(function(joined: Player)
		joined.CharacterAdded:Connect(function()
			task.wait(0.1)
			UpgradeService.applyWalkSpeed(joined)
		end)
	end)
end

return UpgradeService
