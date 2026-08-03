--!strict

--[[
	ToolService

	Unlocking, equipping, and the held placeholder model for the eight heat tools.

	Two validations carry the acceptance criteria:

	  * Unlock is sequential. A tool can only be bought if it is exactly the next one, so a
	    client cannot skip to Mini Sun by naming index 8. Cost comes from ContentConfig and
	    the server's own reading of HighestTool.
	  * Equip requires ownership. `PlayerStateService.setEquippedTool` already refuses an
	    index above HighestTool, so "client cannot equip locked tools" holds even if a
	    future caller forgets to check.

	The held model is rebuilt on equip and on respawn, from ToolVisualConfig. Each tool has
	a visibly different silhouette so a player can see they upgraded without reading a
	number, which is the "Escalating" feel pillar in docs/01.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)
local UtilFolder = Shared:WaitForChild("Util", 10)

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 10))
local ToolVisualConfig = require(ConfigFolder:WaitForChild("ToolVisualConfig", 10))
local Validate = require(UtilFolder:WaitForChild("Validate", 10))

local ServerRoot = script.Parent.Parent
local RemoteRegistry =
	require(ServerRoot:WaitForChild("Runtime", 10):WaitForChild("RemoteRegistry", 10))
local DataService = require(script.Parent:WaitForChild("DataService", 10))
local EconomyService = require(script.Parent:WaitForChild("EconomyService", 10))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService", 10))
local StatsService = require(script.Parent:WaitForChild("StatsService", 10))

local ToolService = {
	Name = "ToolService",
	Priority = 45,
}

local HELD_MODEL_NAME = "IceMeltHeldTool"

local buckets: { [Player]: Validate.TokenBucket } = {}

local function respond(player: Player, action: string, status: string, reason: string?)
	RemoteRegistry.fireClient(RemoteNames.Name.ActionResult, player, {
		Action = action,
		Status = status,
		Reason = reason,
	})
end

-- === Held model ============================================================

local function clearHeldModel(character: Model)
	local existing = character:FindFirstChild(HELD_MODEL_NAME)
	if existing then
		existing:Destroy()
	end
end

--[[
	Builds the placeholder tool into the character's right hand.

	Welded rather than parented to a Tool instance: the game has no equip step by design
	(docs/01), so a Tool with a backpack slot would add exactly the interaction the design
	removes.
]]
local function buildHeldModel(player: Player, toolIndex: number)
	local character = player.Character
	if not character then
		return
	end

	clearHeldModel(character)

	local definition = ContentConfig.Tools[toolIndex]
	if not definition then
		return
	end

	local visual = ToolVisualConfig.Visuals[definition.Key] or ToolVisualConfig.Fallback

	-- R15 and R6 name the hand differently; support both rather than assuming a rig.
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end

	local part = Instance.new("Part")
	part.Name = HELD_MODEL_NAME
	part.Size = visual.Size
	part.Color = visual.Color
	part.Material = visual.Material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.CFrame = hand.CFrame * visual.Offset
	part.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = part
	weld.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Glow"
	emitter.Color = ColorSequence.new(visual.GlowColor)
	emitter.Rate = visual.GlowRate
	emitter.Lifetime = NumberRange.new(0.3, 0.6)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Size = NumberSequence.new(0.5)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.LightEmission = 0.8
	emitter.Parent = part

	local light = Instance.new("PointLight")
	light.Color = visual.GlowColor
	light.Range = 6 + toolIndex
	light.Brightness = 0.5 + toolIndex * 0.2
	light.Parent = part
end

function ToolService.refreshHeldModel(player: Player)
	if not DataService.isLoaded(player) then
		return
	end
	buildHeldModel(player, PlayerStateService.getEquippedTool(player))
end

-- === Purchase and equip ====================================================

--[[
	Unlocks the next tool in sequence. Returns the new index, or nil with a reason.
]]
function ToolService.unlockNext(player: Player): (number?, string?)
	if not DataService.isLoaded(player) then
		return nil, "NoProfile"
	end

	local highest = PlayerStateService.getHighestTool(player)
	local nextIndex = highest + 1

	local definition = ContentConfig.Tools[nextIndex]
	if not definition then
		return nil, "AllToolsOwned"
	end

	if not EconomyService.trySpend(player, definition.Cost, "ToolUnlock") then
		return nil, "Insufficient"
	end

	if not PlayerStateService.setHighestTool(player, nextIndex) then
		EconomyService.grant(player, definition.Cost, "ToolRefund")
		warn(
			string.format(
				"[IceMelt] ToolService: setHighestTool failed for %s; refunded",
				player.Name
			)
		)
		return nil, "Failed"
	end

	-- Equipping the newly bought tool is the obviously intended outcome; making the player
	-- press a second button to feel their purchase would be pointless friction.
	PlayerStateService.setEquippedTool(player, nextIndex)
	StatsService.invalidate(player)
	ToolService.refreshHeldModel(player)

	return nextIndex, nil
end

function ToolService.equip(player: Player, index: number): (boolean, string?)
	if not DataService.isLoaded(player) then
		return false, "NoProfile"
	end
	if not Validate.isIntegerInRange(index, 1, #ContentConfig.Tools) then
		return false, "InvalidPayload"
	end
	if index > PlayerStateService.getHighestTool(player) then
		return false, "NotUnlocked"
	end

	if not PlayerStateService.setEquippedTool(player, index) then
		return false, "Failed"
	end

	StatsService.invalidate(player)
	ToolService.refreshHeldModel(player)
	return true, nil
end

local function consume(player: Player): boolean
	local bucket = buckets[player]
	return bucket ~= nil and Validate.consumeToken(bucket, os.clock())
end

local function onUnlockTool(player: Player)
	if not consume(player) then
		respond(player, "UnlockTool", "Denied", "RateLimited")
		return
	end

	local index, reason = ToolService.unlockNext(player)
	if not index then
		respond(player, "UnlockTool", "Denied", reason)
		return
	end
	respond(player, "UnlockTool", "Ok", nil)
end

local function onEquipTool(player: Player, payload: any)
	if not consume(player) then
		respond(player, "EquipTool", "Denied", "RateLimited")
		return
	end

	if type(payload) ~= "table" then
		respond(player, "EquipTool", "Denied", "InvalidPayload")
		return
	end

	local ok, reason = ToolService.equip(player, (payload :: any).Index)
	if not ok then
		respond(player, "EquipTool", "Denied", reason)
		return
	end
	respond(player, "EquipTool", "Ok", nil)
end

local function onPlayerAdded(player: Player)
	buckets[player] = Validate.newTokenBucket(10, 5, os.clock())

	player.CharacterAdded:Connect(function()
		-- Wait for the rig to assemble before welding anything to a hand.
		task.wait(0.35)
		ToolService.refreshHeldModel(player)
	end)
end

function ToolService.Init()
	RemoteRegistry.connect(RemoteNames.Name.UnlockTool, onUnlockTool)
	RemoteRegistry.connect(RemoteNames.Name.EquipTool, onEquipTool)
end

function ToolService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	for _, player in Players:GetPlayers() do
		if not buckets[player] then
			onPlayerAdded(player)
		end
	end

	-- Give a held tool to anyone whose profile finishes loading after they spawned.
	DataService.getLoadedSignal():Connect(function(player: Player)
		ToolService.refreshHeldModel(player)
	end)
end

return ToolService
