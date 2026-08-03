--!strict

--[[
	MeltEffectsController

	Turns a batched MeltResult into feedback: a steam burst per destroyed cell, one
	aggregated sound per batch, and a Heat popup.

	Everything here is cosmetic and client-only. It reacts to what the server already
	decided; it never adds currency and never changes a cell's state. If this controller
	were deleted the game would still be correct, just dull.

	Two rules from docs/07 are enforced structurally rather than by discipline:

	  * Effect parts come from a fixed pool. A chain reaction that touches sixty cells
	    reuses pooled emitters and drops the excess rather than allocating, so instance
	    count cannot spike with reward size.
	  * One sound per batch, pitched by how much was destroyed. Playing a sound per cell is
	    what makes large chains sound like static.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)

local CollectionService = game:GetService("CollectionService")

local IceFieldConfig = require(ConfigFolder:WaitForChild("IceFieldConfig", 15))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local TagNames = require(ConfigFolder:WaitForChild("TagNames", 15))
local NumberFormatter = require(Shared:WaitForChild("Util", 15):WaitForChild("NumberFormatter", 15))

local RemoteAccess =
	require(script.Parent.Parent:WaitForChild("Runtime", 15):WaitForChild("RemoteAccess", 15))

local MeltEffectsController = {
	Name = "MeltEffectsController",
	Priority = 30,
}

local player = Players.LocalPlayer

local effectPool: { Part } = {}
local poolCursor = 1
local lastSoundAt = 0
local cellsSeen = 0
local heatSeen = 0

function MeltEffectsController.getStats(): (number, number)
	return cellsSeen, heatSeen
end

local function buildPool()
	-- Client-only, so this folder never replicates and costs the server nothing.
	local folder = Instance.new("Folder")
	folder.Name = "IceMeltClientEffects"
	folder.Parent = Workspace

	for index = 1, IceFieldConfig.EffectPoolSize do
		local part = Instance.new("Part")
		part.Name = string.format("Effect_%d", index)
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Steam"
		emitter.Enabled = false
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.25, 0.5)
		emitter.Speed = NumberRange.new(4, 8)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Size = NumberSequence.new(1.2)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 214))
		emitter.LightEmission = 0.6
		emitter.Parent = part

		table.insert(effectPool, part)
	end
end

--[[
	Next pooled emitter, round-robin. Reusing one that is still playing is fine and is far
	better than growing the pool: the visual overlap is invisible at these timings.
]]
local function burstAt(position: Vector3, critical: boolean)
	local part = effectPool[poolCursor]
	if not part then
		return
	end
	poolCursor += 1
	if poolCursor > #effectPool then
		poolCursor = 1
	end

	part.Position = position
	local emitter = part:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Color = ColorSequence.new(
			if critical then Color3.fromRGB(255, 170, 80) else Color3.fromRGB(255, 236, 214)
		)
		emitter:Emit(if critical then 14 else 7)
	end
end

--[[
	One sound for the whole batch, rate-limited, pitched by batch size so a big chain reads
	as bigger rather than louder.
]]
local function playAggregateSound(destroyedCount: number)
	if destroyedCount <= 0 then
		return
	end

	local now = os.clock()
	if now - lastSoundAt < 1 / IceFieldConfig.MaxSoundsPerSecond then
		return
	end
	lastSoundAt = now

	local sound = Instance.new("Sound")
	-- Placeholder: docs/07 lists real crack and hiss audio as a required custom asset.
	sound.SoundId = "rbxasset://sounds/impact_water.mp3"
	sound.Volume = math.clamp(0.25 + destroyedCount * 0.03, 0.25, 0.7)
	sound.PlaybackSpeed = math.clamp(1.15 - destroyedCount * 0.02, 0.8, 1.2)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function showHeatPopup(amount: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromScale(6, 2)
	gui.StudsOffset = Vector3.new(math.random(-2, 2), 3.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	gui.Parent = root

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 196, 120)
	label.TextStrokeTransparency = 0.4
	-- Formatted, not floored. math.floor turned every fractional reward into a smaller whole
	-- number, so after a Thaw a cell worth 1.31 Heat read as "+1" and anything under 1 read
	-- as "+0" while Heat visibly went up. The shared formatter also keeps large late-game
	-- rewards readable instead of printing fifteen digits over the character's head.
	label.Text = string.format("+%s", NumberFormatter.abbreviate(amount))
	label.Parent = gui

	task.delay(0.7, function()
		gui:Destroy()
	end)
end

--[[
	CellId to part, built from the tagged cell instances the server replicated.

	The effect position is read from the real cell part rather than from the payload, so a
	malformed or spoofed result cannot place effects at arbitrary coordinates. An unknown
	id simply produces no effect.
]]
local cellParts: { [number]: BasePart } = {}

local function indexCell(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local cellId = instance:GetAttribute("CellId")
	if type(cellId) == "number" then
		cellParts[cellId] = instance
	end
end

local function buildCellIndex()
	for _, instance in CollectionService:GetTagged(TagNames.IceCell) do
		indexCell(instance)
	end
	CollectionService:GetInstanceAddedSignal(TagNames.IceCell):Connect(indexCell)
	CollectionService:GetInstanceRemovedSignal(TagNames.IceCell):Connect(function(instance)
		local cellId = instance:GetAttribute("CellId")
		if type(cellId) == "number" then
			cellParts[cellId] = nil
		end
	end)
end

--[[
	Effect budget per batch.

	The comment in IceFieldConfig claims excess bursts are dropped. They were not: `burstAt`
	round-robins the pool and drops nothing, so a 120-cell chain issued 120 Emit calls against
	48 parts and produced several hundred particles in a frame. docs/09 asks specifically for
	particle count to be checked, so this is budgeted rather than left to the pool to absorb.

	Chains get a larger budget than a normal melt because a chain is meant to read as bigger,
	but both are bounded independent of how many cells were actually destroyed.
]]
local MAX_BURSTS_PER_BATCH = 12
local MAX_BURSTS_PER_CHAIN = 16

local function onMeltResult(result: any)
	if type(result) ~= "table" or type(result.Cells) ~= "table" then
		return
	end

	-- Gathered first so the budget can be spread across the whole blast rather than spent on
	-- whichever cells happen to come first in the batch.
	local destroyedParts: { BasePart } = {}
	local destroyedCritical: { boolean } = {}
	local destroyed = 0

	for _, entry in result.Cells do
		if type(entry) == "table" and entry.Destroyed then
			destroyed += 1
			local part = cellParts[entry.CellId]
			if part then
				table.insert(destroyedParts, part)
				table.insert(destroyedCritical, entry.Critical == true)
			end
		end
	end

	local isChain = type(result.ChainKey) == "string"
	local budget = if isChain then MAX_BURSTS_PER_CHAIN else MAX_BURSTS_PER_BATCH
	local count = #destroyedParts

	if count > 0 then
		if count <= budget then
			for index = 1, count do
				burstAt(destroyedParts[index].Position, destroyedCritical[index])
			end
		else
			--[[
				Even stride rather than the first N. Truncating would cluster every burst in
				one corner of a 48-stud blast and leave the rest of it unlit, which reads as a
				bug rather than as a large explosion.
			]]
			for slot = 1, budget do
				local index = math.floor((slot - 0.5) * count / budget) + 1
				index = math.clamp(index, 1, count)
				burstAt(destroyedParts[index].Position, destroyedCritical[index])
			end
		end
	end

	cellsSeen += destroyed
	heatSeen += tonumber(result.HeatGranted) or 0

	playAggregateSound(destroyed)

	local heat = tonumber(result.HeatGranted) or 0
	if heat > 0 then
		showHeatPopup(heat)
	end
end

function MeltEffectsController.Init()
	buildPool()
	buildCellIndex()
	RemoteAccess.connect(RemoteNames.Name.MeltResult, onMeltResult)
end

return MeltEffectsController
