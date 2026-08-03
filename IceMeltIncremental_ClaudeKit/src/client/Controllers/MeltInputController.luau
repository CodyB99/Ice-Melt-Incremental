--!strict

--[[
	MeltInputController

	Drives the melt loop. There is deliberately no button and no equip step: docs/01 calls
	for melting to feel immediate, and the first melt must happen within five seconds of
	spawning. Walking into ice is the whole interaction, so this simply pulses on a timer
	while the character is alive.

	That also means the same code path covers touch, keyboard, and controller without any
	per-device input handling, which is the mobile-first requirement met for free.

	The client's only authority is asking. It sends a monotonically increasing sequence
	number; the server derives position, zone, stats, targets, damage, and reward. Nothing
	here grants anything.

	Pulse rate is kept just under the server's token bucket. Matching it exactly would
	leave no headroom for jitter and would show up as intermittent RateLimited rejections.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 15))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 15))
local IceFieldConfig = require(ConfigFolder:WaitForChild("IceFieldConfig", 15))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 15))

local RemoteAccess =
	require(script.Parent.Parent:WaitForChild("Runtime", 15):WaitForChild("RemoteAccess", 15))

local MeltInputController = {
	Name = "MeltInputController",
	Priority = 20,
}

local player = Players.LocalPlayer

-- Just under the server's sustained allowance, leaving headroom for network jitter.
local PULSE_INTERVAL = 1 / (GameConfig.Limits.MaxMeltPulsesPerSecond - 2)

local sequence = 0
local accumulator = 0
local pulsesSent = 0

function MeltInputController.getPulsesSent(): number
	return pulsesSent
end

local function characterRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root
end

--[[
	Is the character close enough to any ice field for a pulse to be worth sending?

	Without this the client fires ten remotes a second forever, including while standing in
	the hub with no ice for fifty studs. Every one of those is bandwidth and a server-side
	validation for a guaranteed rejection.

	This is a bandwidth optimisation, not a security check. Skipping the send only means
	the client declines to ask; the server still validates every pulse that does arrive,
	and a modified client that ignores this gains nothing but rejections.

	The bounds are a rectangle per zone plus the maximum possible melt radius, so this can
	never suppress a pulse that would have succeeded.
]]
local FIELD_HALF_EXTENT = ((IceFieldConfig.GridSize - 1) / 2) * IceFieldConfig.Spacing
local FIELD_MARGIN = BalanceConfig.Melt.MaxRadiusStuds

local function nearAnyIceField(position: Vector3): boolean
	for _, zoneKey in WorldConfig.ZoneOrder do
		local layout = WorldConfig.Zones[zoneKey]
		if layout then
			local dx = math.abs(position.X - layout.Center.X)
			local dz = math.abs(position.Z - layout.Center.Z)
			if
				dx <= FIELD_HALF_EXTENT + FIELD_MARGIN
				and dz <= FIELD_HALF_EXTENT + FIELD_MARGIN
			then
				return true
			end
		end
	end
	return false
end

function MeltInputController.Start()
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator < PULSE_INTERVAL then
			return
		end
		accumulator = 0

		local root = characterRoot()
		if not root then
			return
		end

		if not nearAnyIceField(root.Position) then
			return
		end

		sequence += 1
		pulsesSent += 1

		-- The payload carries only a sequence number. Sending a position or a target list
		-- would be pointless: the server ignores both and derives its own.
		RemoteAccess.fire(RemoteNames.Name.MeltPulse, { Sequence = sequence })
	end)
end

return MeltInputController
