--!strict

--[[
	DebugOverlayController

	Small development-only readout: pulses sent, cells destroyed, Heat, and any melt
	rejections with their reason.

	Only created when GameConfig.Debug.ShowMeltDiagnostics is set, which is Development
	only, so it cannot ship to players by accident.

	Rejection reasons arrive on ActionResult, which the server also only sends in
	development. That pairing matters: on a live server, telling a client exactly which
	validation it failed is free tuning information for someone building an exploit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)
local UtilFolder = Shared:WaitForChild("Util", 15)

local GameConfig = require(ConfigFolder:WaitForChild("GameConfig", 15))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local NumberFormatter = require(UtilFolder:WaitForChild("NumberFormatter", 15))

local ControllersFolder = script.Parent
local RemoteAccess =
	require(script.Parent.Parent:WaitForChild("Runtime", 15):WaitForChild("RemoteAccess", 15))

local DebugOverlayController = {
	Name = "DebugOverlayController",
	-- Last, so the controllers it reads from are already registered.
	Priority = 500,
}

local rejections: { [string]: number } = {}
local rejectionTotal = 0

local function onActionResult(result: any)
	if type(result) ~= "table" or result.Action ~= "MeltPulse" then
		return
	end
	if result.Status == "Ok" then
		return
	end

	local reason = tostring(result.Reason)
	rejections[reason] = (rejections[reason] or 0) + 1
	rejectionTotal += 1
end

function DebugOverlayController.getRejections(): ({ [string]: number }, number)
	return table.clone(rejections), rejectionTotal
end

function DebugOverlayController.Init()
	if not GameConfig.Debug.ShowMeltDiagnostics then
		return
	end
	RemoteAccess.connect(RemoteNames.Name.ActionResult, onActionResult)
end

function DebugOverlayController.Start()
	if not GameConfig.Debug.ShowMeltDiagnostics then
		return
	end

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 15)
	if not playerGui then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IceMeltDebugOverlay"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 1000
	screenGui.Parent = playerGui

	local label = Instance.new("TextLabel")
	-- Top-left, away from the thumb-safe zones docs/06 reserves for real UI.
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.new(0, 8, 0, 8)
	label.Size = UDim2.new(0, 300, 0, 96)
	label.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(190, 230, 255)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = label

	local meltInput = ControllersFolder:FindFirstChild("MeltInputController")
	local meltEffects = ControllersFolder:FindFirstChild("MeltEffectsController")
	local inputController = if meltInput then require(meltInput) else nil
	local effectsController = if meltEffects then require(meltEffects) else nil

	local accumulator = 0
	RunService.RenderStepped:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator < 0.25 then
			return
		end
		accumulator = 0

		local pulses = if inputController then inputController.getPulsesSent() else 0
		local cells, heat = 0, 0
		if effectsController then
			cells, heat = effectsController.getStats()
		end

		local reasonText = "none"
		if rejectionTotal > 0 then
			local parts = {}
			for reason, count in rejections do
				table.insert(parts, string.format("%s=%d", reason, count))
			end
			table.sort(parts)
			reasonText = table.concat(parts, " ")
		end

		label.Text = string.format(
			"IceMelt debug (%s)\npulses sent : %d\ncells melted: %d\nheat earned : %s\nrejections  : %d %s",
			GameConfig.Environment,
			pulses,
			cells,
			NumberFormatter.abbreviate(heat),
			rejectionTotal,
			reasonText
		)
	end)
end

return DebugOverlayController
