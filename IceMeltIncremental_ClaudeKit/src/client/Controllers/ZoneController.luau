--!strict

--[[
	ZoneController

	Applies each zone's lighting and ambience as the player travels.

	Client-side on purpose. Lighting is a single global object, so setting it on the server
	would give every player the look of whichever zone someone entered most recently. Doing
	it per client means each player sees the zone they are actually standing in, which is
	the only correct behaviour once players can be in different zones at once.

	Transitions are tweened rather than snapped, because an instant swap between the bright
	Backyard and the dark Cavern reads as a glitch.

	Purely cosmetic. Nothing here affects what the server allows.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)

local ZoneStyleConfig = require(ConfigFolder:WaitForChild("ZoneStyleConfig", 15))

local ControllersFolder = script.Parent

local ZoneController = {
	Name = "ZoneController",
	Priority = 45,
}

local TRANSITION = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local appliedZone: string? = nil

function ZoneController.getAppliedZone(): string?
	return appliedZone
end

local function applyZone(zoneKey: string)
	if zoneKey == appliedZone then
		return
	end

	local style = ZoneStyleConfig.Styles[zoneKey]
	if not style then
		return
	end
	appliedZone = zoneKey

	TweenService:Create(Lighting, TRANSITION, {
		Ambient = style.Ambient,
		OutdoorAmbient = style.OutdoorAmbient,
		FogColor = style.FogColor,
		FogEnd = style.FogEnd,
		Brightness = style.Brightness,
	}):Play()
end

function ZoneController.Start()
	local stateController = ControllersFolder:FindFirstChild("StateController")
	if not stateController then
		warn("[IceMelt] ZoneController: StateController missing")
		return
	end

	local controller = require(stateController)

	local existing = controller.get()
	if existing and existing.CurrentZone then
		applyZone(existing.CurrentZone)
	end

	controller.getChangedSignal():Connect(function(state)
		if state and state.CurrentZone then
			applyZone(state.CurrentZone)
		end
	end)
end

return ZoneController
