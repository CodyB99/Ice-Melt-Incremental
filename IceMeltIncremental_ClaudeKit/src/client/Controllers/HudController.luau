--!strict

--[[
	HudController

	Heat balance, seven upgrade cards, and the tool panel.

	Layout follows docs/06: the balance sits top-left, and every control lives in a
	right-hand thumb-safe column so nothing covers the character or the melt radius on a
	phone. Panels are closed by default and only one is open at a time, so the play area
	stays clear.

	What this displays and what it computes are deliberately different things:

	  * Current stats come from the server in the replicated snapshot. The client never
	    recomputes what a player's radius or damage actually is.
	  * The "after" side of an upgrade preview is a hypothetical the server has no reason
	    to send for every unbought level, so it is computed locally from the same shared
	    config and the same StatMath the server uses. It is display only; buying still goes
	    through the server, which derives the real cost and effect itself.

	Costs come from StatMath.upgradeCost and ContentConfig, never from a literal, so the
	numbers on screen cannot drift from the numbers charged.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)
local UtilFolder = Shared:WaitForChild("Util", 15)

local BalanceConfig = require(ConfigFolder:WaitForChild("BalanceConfig", 15))
local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 15))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local NumberFormatter = require(UtilFolder:WaitForChild("NumberFormatter", 15))
local StatMath = require(UtilFolder:WaitForChild("StatMath", 15))
local Types = require(Shared:WaitForChild("Types", 15))

local ControllersFolder = script.Parent
local RemoteAccess =
	require(script.Parent.Parent:WaitForChild("Runtime", 15):WaitForChild("RemoteAccess", 15))

type ReplicatedPlayerState = Types.ReplicatedPlayerState

local HudController = {
	Name = "HudController",
	Priority = 40,
}

local COLOR_BG = Color3.fromRGB(16, 22, 34)
local COLOR_PANEL = Color3.fromRGB(24, 32, 48)
local COLOR_TEXT = Color3.fromRGB(232, 242, 255)
local COLOR_MUTED = Color3.fromRGB(150, 172, 200)
local COLOR_AFFORD = Color3.fromRGB(64, 168, 106)
local COLOR_DENY = Color3.fromRGB(70, 78, 94)
local COLOR_HEAT = Color3.fromRGB(255, 186, 96)

local player = Players.LocalPlayer
local state: ReplicatedPlayerState? = nil

local heatLabel: TextLabel? = nil
local toolLabel: TextLabel? = nil
local upgradeRows: { [string]: { Card: Frame, Title: TextLabel, Detail: TextLabel, Buy: TextButton } } =
	{}
local toolTitle: TextLabel? = nil
local toolDetail: TextLabel? = nil
local toolBuy: TextButton? = nil
local panels: { [string]: Frame } = {}

-- === Small builders ========================================================

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function padding(parent: Instance, pixels: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, pixels)
	p.PaddingRight = UDim.new(0, pixels)
	p.PaddingTop = UDim.new(0, pixels)
	p.PaddingBottom = UDim.new(0, pixels)
	p.Parent = parent
end

local function label(parent: Instance, text: string, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

-- === Formatting ============================================================

--[[
	Human-readable form of one upgrade's effect. Multiplier tracks read as "x1.25",
	additive ones in their own unit, and Crit as a percentage.
]]
local function formatEffect(key: string, level: number): string
	local definition = BalanceConfig.Upgrades[key]
	if not definition then
		return "-"
	end

	local value = StatMath.upgradeEffect(key, level)

	if key == "Crit" then
		return NumberFormatter.percent(value)
	end
	if definition.Scaling == "Multiplier" then
		return NumberFormatter.multiplier(value)
	end
	if key == "Auto" then
		return string.format("%.1f/s", value)
	end
	return string.format("%.2f", value)
end

-- === Panels ================================================================

local function makePanel(parent: Instance, name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -12, 1, -84)
	frame.Size = UDim2.new(0, 320, 0, 340)
	frame.BackgroundColor3 = COLOR_PANEL
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	frame.Parent = parent
	corner(frame, 10)
	padding(frame, 10)
	panels[name] = frame
	return frame
end

local function togglePanel(name: string)
	for panelName, frame in panels do
		frame.Visible = panelName == name and not frame.Visible
	end
end

local function buildUpgradePanel(parent: Instance)
	local frame = makePanel(parent, "Upgrades")

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for index, key in BalanceConfig.UpgradeOrder do
		local definition = BalanceConfig.Upgrades[key]

		local card = Instance.new("Frame")
		card.Name = key
		card.Size = UDim2.new(1, -8, 0, 60)
		card.BackgroundColor3 = COLOR_BG
		card.LayoutOrder = index
		card.Parent = list
		corner(card, 8)
		padding(card, 8)

		local title = label(card, definition.DisplayName, 14, COLOR_TEXT)
		title.Size = UDim2.new(1, -90, 0, 18)

		local detail = label(card, "", 12, COLOR_MUTED)
		detail.Position = UDim2.new(0, 0, 0, 20)
		detail.Size = UDim2.new(1, -90, 0, 26)
		detail.TextWrapped = true

		local buy = Instance.new("TextButton")
		buy.Name = "Buy"
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, 0, 0.5, 0)
		buy.Size = UDim2.new(0, 82, 0, 40)
		buy.BackgroundColor3 = COLOR_DENY
		buy.Font = Enum.Font.GothamBold
		buy.TextSize = 12
		buy.TextColor3 = COLOR_TEXT
		buy.Text = "-"
		buy.AutoButtonColor = true
		buy.Parent = card
		corner(buy, 6)

		buy.Activated:Connect(function()
			-- The request names the upgrade and nothing else. There is no cost, level, or
			-- quantity in the message for anyone to tamper with.
			RemoteAccess.fire(RemoteNames.Name.PurchaseUpgrade, { Key = key })
		end)

		upgradeRows[key] = { Card = card, Title = title, Detail = detail, Buy = buy }
	end
end

local function buildToolPanel(parent: Instance)
	local frame = makePanel(parent, "Tools")

	toolTitle = label(frame, "", 16, COLOR_TEXT);
	(toolTitle :: TextLabel).Size = UDim2.new(1, 0, 0, 22)

	toolDetail = label(frame, "", 12, COLOR_MUTED);
	(toolDetail :: TextLabel).Position = UDim2.new(0, 0, 0, 26);
	(toolDetail :: TextLabel).Size = UDim2.new(1, 0, 0, 60);
	(toolDetail :: TextLabel).TextWrapped = true

	local buy = Instance.new("TextButton")
	buy.Size = UDim2.new(1, 0, 0, 44)
	buy.Position = UDim2.new(0, 0, 0, 92)
	buy.BackgroundColor3 = COLOR_DENY
	buy.Font = Enum.Font.GothamBold
	buy.TextSize = 14
	buy.TextColor3 = COLOR_TEXT
	buy.Text = "Unlock"
	buy.Parent = frame
	corner(buy, 8)
	buy.Activated:Connect(function()
		-- Unlock is always "the next tool", so there is no index to send or forge.
		RemoteAccess.fire(RemoteNames.Name.UnlockTool)
	end)
	toolBuy = buy
end

-- === Refresh ===============================================================

local function refresh()
	local current = state
	if not current then
		return
	end

	local heat = current.Heat

	if heatLabel then
		heatLabel.Text = string.format("%s Heat", NumberFormatter.abbreviate(heat))
	end

	local equipped = ContentConfig.Tools[current.EquippedTool]
	if toolLabel and equipped then
		toolLabel.Text = string.format(
			"%s   dmg %s   radius %.1f",
			equipped.DisplayName,
			NumberFormatter.abbreviate(current.Stats.Damage),
			current.Stats.Radius
		)
	end

	for key, row in upgradeRows do
		local definition = BalanceConfig.Upgrades[key]
		local level = (current.Upgrades :: any)[key] or 0
		local cost = StatMath.upgradeCost(key, level)

		row.Title.Text = string.format("%s   Lv %d", definition.DisplayName, level)

		if cost == nil then
			row.Detail.Text = string.format("%s   MAX", formatEffect(key, level))
			row.Buy.Text = "MAX"
			row.Buy.BackgroundColor3 = COLOR_DENY
		else
			-- Explicit before and after, which is the phase's "clear before/after feedback".
			row.Detail.Text =
				string.format("%s  ->  %s", formatEffect(key, level), formatEffect(key, level + 1))
			row.Buy.Text = NumberFormatter.abbreviate(cost)
			row.Buy.BackgroundColor3 = if heat >= cost then COLOR_AFFORD else COLOR_DENY
		end
	end

	local nextIndex = current.HighestTool + 1
	local nextTool = ContentConfig.Tools[nextIndex]

	if toolTitle and toolDetail and toolBuy then
		if not nextTool then
			toolTitle.Text = "All tools owned"
			toolDetail.Text =
				string.format("Equipped: %s", if equipped then equipped.DisplayName else "-")
			toolBuy.Text = "MAX"
			toolBuy.BackgroundColor3 = COLOR_DENY
		else
			local currentTool = ContentConfig.Tools[current.HighestTool]
			toolTitle.Text = string.format("Next tool: %s", nextTool.DisplayName)
			toolDetail.Text = string.format(
				"Power %s  ->  %s\nRadius +%.2f  ->  +%.2f",
				NumberFormatter.multiplier(if currentTool then currentTool.Power else 1),
				NumberFormatter.multiplier(nextTool.Power),
				if currentTool then currentTool.Radius else 0,
				nextTool.Radius
			)
			toolBuy.Text = string.format("Unlock  %s", NumberFormatter.abbreviate(nextTool.Cost))
			toolBuy.BackgroundColor3 = if heat >= nextTool.Cost then COLOR_AFFORD else COLOR_DENY
		end
	end
end

-- === Lifecycle =============================================================

function HudController.Start()
	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not playerGui then
		warn("[IceMelt] HudController: no PlayerGui")
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IceMeltHud"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Balance, top-left, away from the thumb zones.
	local topBar = Instance.new("Frame")
	topBar.Position = UDim2.new(0, 12, 0, 12)
	topBar.Size = UDim2.new(0, 300, 0, 54)
	topBar.BackgroundColor3 = COLOR_BG
	topBar.BackgroundTransparency = 0.15
	topBar.Parent = screenGui
	corner(topBar, 10)
	padding(topBar, 10)

	heatLabel = label(topBar, "0 Heat", 20, COLOR_HEAT);
	(heatLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 22);
	(heatLabel :: TextLabel).Font = Enum.Font.GothamBold

	toolLabel = label(topBar, "", 12, COLOR_MUTED);
	(toolLabel :: TextLabel).Position = UDim2.new(0, 0, 0, 24);
	(toolLabel :: TextLabel).Size = UDim2.new(1, 0, 0, 16)

	buildUpgradePanel(screenGui)
	buildToolPanel(screenGui)

	-- Right-hand thumb column.
	local buttonRow = Instance.new("Frame")
	buttonRow.AnchorPoint = Vector2.new(1, 1)
	buttonRow.Position = UDim2.new(1, -12, 1, -12)
	buttonRow.Size = UDim2.new(0, 320, 0, 60)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = screenGui

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowLayout.Parent = buttonRow

	for _, entry in
		{ { Name = "Upgrades", Panel = "Upgrades" }, { Name = "Tools", Panel = "Tools" } }
	do
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 120, 1, 0)
		button.BackgroundColor3 = COLOR_PANEL
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = COLOR_TEXT
		button.Text = entry.Name
		button.Parent = buttonRow
		corner(button, 10)
		button.Activated:Connect(function()
			togglePanel(entry.Panel)
		end)
	end

	local stateController = ControllersFolder:FindFirstChild("StateController")
	if not stateController then
		warn("[IceMelt] HudController: StateController missing")
		return
	end

	local controller = require(stateController)
	state = controller.get()
	refresh()

	controller.getChangedSignal():Connect(function(newState)
		state = newState
		refresh()
	end)
end

return HudController
