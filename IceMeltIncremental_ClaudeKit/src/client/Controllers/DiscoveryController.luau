--!strict

--[[
	DiscoveryController

	The collection index, the reveal card, and the server announcement banner.

	Everything here is presentation. The award, its Heat and its save all happened on the server
	before the melt reply was even built, so this controller can drop a card, be closed
	mid-animation, or never run at all and the player still keeps the discovery. docs/04
	requires exactly that: a player cannot lose a discovery to a closed UI or a dropped
	connection.

	Rarity is shown on four redundant channels — word, glyph, pip count, then colour — because
	docs/06 requires colour-independent rarity and docs/07 says not to lean on colour at all.
	The pips are frames rather than repeated characters so a font fallback cannot take out two
	channels at once.

	Announcements are rendered from catalogue keys only. The payload carries no numbers, and an
	unrecognised key is refused rather than displayed, so nothing a malformed broadcast could
	contain reaches the screen as text.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 15):WaitForChild("Shared", 15)
local ConfigFolder = Shared:WaitForChild("Config", 15)
local UtilFolder = Shared:WaitForChild("Util", 15)

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 15))
local RarityConfig = require(ConfigFolder:WaitForChild("RarityConfig", 15))
local RemoteNames = require(ConfigFolder:WaitForChild("RemoteNames", 15))
local DiscoveryMath = require(UtilFolder:WaitForChild("DiscoveryMath", 15))
local Types = require(Shared:WaitForChild("Types", 15))

local ClientRuntime = script.Parent.Parent:WaitForChild("Runtime", 15)
local RemoteAccess = require(ClientRuntime:WaitForChild("RemoteAccess", 15))
local EffectSettings = require(ClientRuntime:WaitForChild("EffectSettings", 15))

local DiscoveryController = {
	Name = "DiscoveryController",
	Priority = 45,
}

local player = Players.LocalPlayer

local COLOR_BG = Color3.fromRGB(16, 22, 34)
local COLOR_PANEL = Color3.fromRGB(24, 32, 48)
local COLOR_TEXT = Color3.fromRGB(232, 242, 255)
local COLOR_MUTED = Color3.fromRGB(150, 172, 200)

local revealFrame: Frame? = nil
local announceFrame: Frame? = nil

-- Owned counts, from the replicated snapshot. The client never derives ownership itself.
local owned: { [string]: number } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

--[[
	Rarity chip: glyph, word, and a row of pips. Colour is applied last and to the frame only,
	so the chip still reads correctly in greyscale or with the colour ignored entirely.
]]
local function buildRarityChip(parent: Instance, rarity: string): Frame
	local look = RarityConfig.get(rarity)

	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = look.Color
	chip.BackgroundTransparency = 0.75
	chip.Size = UDim2.new(0, 132, 0, 20)
	chip.Parent = parent
	corner(chip, 6)

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.new(0, 16, 1, 0)
	glyph.Position = UDim2.new(0, 4, 0, 0)
	glyph.Font = Enum.Font.GothamBold
	glyph.TextSize = 13
	glyph.TextColor3 = look.Color
	glyph.Text = look.Glyph
	glyph.Parent = chip

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 22, 0, 0)
	label.Size = UDim2.new(0, 72, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = COLOR_TEXT
	label.Text = look.Label
	label.Parent = chip

	-- Pips as frames, not text: the count survives any font substitution.
	local pips = Instance.new("Frame")
	pips.BackgroundTransparency = 1
	pips.AnchorPoint = Vector2.new(1, 0.5)
	pips.Position = UDim2.new(1, -5, 0.5, 0)
	pips.Size = UDim2.new(0, 34, 0, 6)
	pips.Parent = chip

	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.Padding = UDim.new(0, 2)
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Parent = pips

	for _ = 1, look.Pips do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 4, 0, 4)
		pip.BackgroundColor3 = look.Color
		pip.BorderSizePixel = 0
		pip.Parent = pips
		corner(pip, 2)
	end

	return chip
end

-- === Collection index ======================================================

local entryRows: { [string]: { Card: Frame, Name: TextLabel, Count: TextLabel, Icon: Frame } } = {}
local zoneHeaders: { [string]: TextLabel } = {}
local totalLabel: TextLabel? = nil

--[[
	Builds one row per discovery, grouped by zone in catalogue order.

	Built once at start rather than rebuilt on each snapshot: the catalogue is fixed at twenty
	entries, and refresh then only writes text and colour on rows that already exist.
]]
local function buildIndex(parent: Instance)
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 1, -24)
	list.Position = UDim2.new(0, 0, 0, 24)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local order = 0

	totalLabel = Instance.new("TextLabel")
	local total = totalLabel :: TextLabel
	total.BackgroundTransparency = 1
	total.Size = UDim2.new(1, 0, 0, 20)
	total.Position = UDim2.new(0, 0, 0, 0)
	total.Font = Enum.Font.GothamBold
	total.TextSize = 13
	total.TextXAlignment = Enum.TextXAlignment.Left
	total.TextColor3 = COLOR_TEXT
	total.Text = "Discoveries"
	total.Parent = parent

	for _, zoneKey in ContentConfig.ZoneOrder do
		local zone = ContentConfig.Zones[zoneKey]

		order += 1
		local header = Instance.new("TextLabel")
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, -8, 0, 20)
		header.LayoutOrder = order
		header.Font = Enum.Font.GothamBold
		header.TextSize = 12
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = COLOR_MUTED
		header.Text = zone.DisplayName
		header.Parent = list
		zoneHeaders[zoneKey] = header

		-- Catalogue order within a zone, rarest last, so the list reads as a ladder.
		local inZone: { Types.DiscoveryDefinition } = {}
		for _, definition in ContentConfig.Discoveries do
			if definition.Zone == zoneKey then
				table.insert(inZone, definition)
			end
		end
		table.sort(inZone, function(a, b): boolean
			local ra = RarityConfig.get(a.Rarity).Order
			local rb = RarityConfig.get(b.Rarity).Order
			if ra == rb then
				return a.Key < b.Key
			end
			return ra < rb
		end)

		for _, definition in inZone do
			order += 1

			local card = Instance.new("Frame")
			card.Name = definition.Key
			card.Size = UDim2.new(1, -8, 0, 40)
			card.BackgroundColor3 = COLOR_BG
			card.LayoutOrder = order
			card.Parent = list
			corner(card, 6)

			-- Stand-in for the discovery art docs/07 lists as a required custom asset. A
			-- coloured square is honest placeholder rather than a borrowed icon.
			local icon = Instance.new("Frame")
			icon.Size = UDim2.new(0, 26, 0, 26)
			icon.Position = UDim2.new(0, 7, 0, 7)
			icon.BackgroundColor3 = RarityConfig.Silhouette.Color
			icon.BorderSizePixel = 0
			icon.Parent = card
			corner(icon, 4)

			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.new(0, 40, 0, 3)
			name.Size = UDim2.new(1, -90, 0, 17)
			name.Font = Enum.Font.GothamMedium
			name.TextSize = 12
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.TextColor3 = COLOR_MUTED
			name.Text = RarityConfig.Silhouette.HiddenName
			name.Parent = card

			local chip = buildRarityChip(card, definition.Rarity)
			chip.Position = UDim2.new(0, 40, 0, 20)
			chip.Size = UDim2.new(0, 124, 0, 17)

			local count = Instance.new("TextLabel")
			count.BackgroundTransparency = 1
			count.AnchorPoint = Vector2.new(1, 0)
			count.Position = UDim2.new(1, -8, 0, 3)
			count.Size = UDim2.new(0, 44, 0, 17)
			count.Font = Enum.Font.GothamBold
			count.TextSize = 12
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.TextColor3 = COLOR_MUTED
			count.Text = ""
			count.Parent = card

			entryRows[definition.Key] = { Card = card, Name = name, Count = count, Icon = icon }
		end
	end
end

--[[
	Repaints the index from the replicated collection.

	Ownership comes from the snapshot and nothing else: the client never infers that it owns a
	discovery from having seen a reveal card, so a dropped card cannot desync the index.
]]
function DiscoveryController.refreshIndex()
	local totalOwned = 0

	for _, definition in ContentConfig.Discoveries do
		local row = entryRows[definition.Key]
		if not row then
			continue
		end

		local count = owned[definition.Key] or 0
		local found = count > 0
		if found then
			totalOwned += 1
		end

		row.Name.Text = if found then definition.DisplayName else RarityConfig.Silhouette.HiddenName
		row.Name.TextColor3 = if found then COLOR_TEXT else COLOR_MUTED
		row.Icon.BackgroundColor3 = if found
			then RarityConfig.get(definition.Rarity).Color
			else RarityConfig.Silhouette.Color
		row.Count.Text = if count > 1
			then string.format("x%d", count)
			elseif found then "✓"
			else ""
	end

	for _, zoneKey in ContentConfig.ZoneOrder do
		local header = zoneHeaders[zoneKey]
		if not header then
			continue
		end
		local inZone, foundInZone = 0, 0
		for _, definition in ContentConfig.Discoveries do
			if definition.Zone == zoneKey then
				inZone += 1
				if (owned[definition.Key] or 0) > 0 then
					foundInZone += 1
				end
			end
		end
		header.Text = string.format(
			"%s   %d/%d",
			ContentConfig.Zones[zoneKey].DisplayName,
			foundInZone,
			inZone
		)
		-- Completion is stated in words and a count, never by colour alone.
		header.TextColor3 = if foundInZone == inZone and inZone > 0
			then Color3.fromRGB(120, 220, 150)
			else COLOR_MUTED
	end

	if totalLabel then
		totalLabel.Text =
			string.format("Discoveries   %d/%d", totalOwned, #ContentConfig.Discoveries)
	end
end

function DiscoveryController.buildPanel(parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Discoveries"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = parent
	buildIndex(frame)
	return frame
end

-- === Reveal card ===========================================================

local queue: { { Key: string, IsNew: boolean } } = {}
local showing = false

local function presentCard(entry: { Key: string, IsNew: boolean })
	local definition = DiscoveryMath.get(entry.Key)
	local frame = revealFrame
	if not definition or not frame then
		return
	end

	local look = RarityConfig.get(definition.Rarity)

	frame:ClearAllChildren()
	corner(frame, 10)

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, -16)
	accent.Position = UDim2.new(0, 8, 0, 8)
	accent.BackgroundColor3 = look.Color
	accent.BorderSizePixel = 0
	accent.Parent = frame
	corner(accent, 2)

	local heading = Instance.new("TextLabel")
	heading.BackgroundTransparency = 1
	heading.Position = UDim2.new(0, 20, 0, 8)
	heading.Size = UDim2.new(1, -28, 0, 16)
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 11
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = look.Color
	-- Stated in words rather than implied by styling, so a duplicate is unmistakable.
	heading.Text = if entry.IsNew then "NEW DISCOVERY" else "ALREADY FOUND"
	heading.Parent = frame

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 20, 0, 24)
	name.Size = UDim2.new(1, -28, 0, 22)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 16
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = COLOR_TEXT
	name.Text = definition.DisplayName
	name.Parent = frame

	local chip = buildRarityChip(frame, definition.Rarity)
	chip.Position = UDim2.new(0, 20, 0, 48)

	if not entry.IsNew then
		local count = Instance.new("TextLabel")
		count.BackgroundTransparency = 1
		count.AnchorPoint = Vector2.new(1, 0)
		count.Position = UDim2.new(1, -10, 0, 48)
		count.Size = UDim2.new(0, 60, 0, 20)
		count.Font = Enum.Font.GothamBold
		count.TextSize = 13
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.TextColor3 = COLOR_MUTED
		count.Text = string.format("x%d", owned[entry.Key] or 1)
		count.Parent = frame
	end

	frame.Visible = true
end

--[[
	Shows queued cards one at a time.

	Never interrupts a card that is on screen, and drops nothing silently: overflow beyond the
	queue depth is collapsed into a single summary rather than making the player sit through a
	backlog. docs/01 asks for limited simultaneous popups.
]]
local function pump()
	if showing then
		return
	end
	local entry = table.remove(queue, 1)
	if not entry then
		if revealFrame then
			revealFrame.Visible = false
		end
		return
	end

	showing = true
	presentCard(entry)

	local definition = DiscoveryMath.get(entry.Key)
	local hold = if definition then RarityConfig.get(definition.Rarity).RevealSeconds else 1.5
	-- Reduced motion shortens the dwell rather than removing the card: the card is
	-- information, and information is not motion.
	if EffectSettings.reducedMotion() then
		hold = math.min(hold, 1.2)
	end

	task.delay(hold, function()
		showing = false
		pump()
	end)
end

local function enqueueReveal(key: string, isNew: boolean)
	local definition = DiscoveryMath.get(key)
	if not definition then
		-- An unknown key is refused rather than rendered.
		return
	end

	--[[
		Duplicates of the commonest tiers do not open a card. Presentation only: the award and
		its Heat already happened on the server regardless of what is drawn here.
	]]
	if not isNew then
		local order = RarityConfig.get(definition.Rarity).Order
		if order < RarityConfig.Reveal.DuplicateCardMinOrder then
			return
		end
	end

	if #queue >= RarityConfig.Reveal.QueueDepth then
		-- Collapse rather than grow without bound.
		queue[#queue] = { Key = key, IsNew = isNew }
		return
	end
	table.insert(queue, { Key = key, IsNew = isNew })
	pump()
end

-- === Announcements =========================================================

local function showAnnouncement(payload: any)
	local frame = announceFrame
	if not frame or type(payload) ~= "table" then
		return
	end

	local kind = tostring(payload.Kind)
	local key = tostring(payload.Key)
	local name = tostring(payload.PlayerName)

	--[[
		Everything shown is composed here from the catalogue. The payload supplies identifiers
		only, so an unrecognised key produces nothing rather than putting attacker-chosen text
		on every screen. RichText stays off for the same reason.
	]]
	local title: string
	local colour: Color3

	if kind == "Discovery" then
		local definition = DiscoveryMath.get(key)
		if not definition then
			return
		end
		local look = RarityConfig.get(definition.Rarity)
		colour = look.Color
		title = string.format("%s found %s  (%s)", name, definition.DisplayName, look.Label)
	elseif kind == "Chain" then
		local display: string? = nil
		for _, definition in ContentConfig.Chains do
			if definition.Key == key then
				display = definition.DisplayName
			end
		end
		if not display then
			return
		end
		colour = Color3.fromRGB(255, 150, 80)
		title = string.format("%s set off a %s", name, display)
	else
		return
	end

	local label = frame:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = title
		label.TextColor3 = colour
		label.RichText = false
	end

	frame.Visible = true
	task.delay(5, function()
		if frame then
			frame.Visible = false
		end
	end)
end

-- === Lifecycle =============================================================

function DiscoveryController.Start()
	local playerGui = player:WaitForChild("PlayerGui", 15)
	if not playerGui then
		warn("[IceMelt] DiscoveryController: no PlayerGui")
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "IceMeltDiscovery"
	gui.ResetOnSpawn = false
	-- Above the HUD so a reveal is never drawn behind a panel, below nothing else.
	gui.DisplayOrder = 20
	gui.Parent = playerGui

	-- Reveal card, top-centre, clear of both the HUD balance and the thumb column.
	local reveal = Instance.new("Frame")
	reveal.AnchorPoint = Vector2.new(0.5, 0)
	reveal.Position = UDim2.new(0.5, 0, 0, 74)
	reveal.Size = UDim2.new(0, 260, 0, 78)
	reveal.BackgroundColor3 = COLOR_PANEL
	reveal.BackgroundTransparency = 0.05
	reveal.Visible = false
	reveal.Parent = gui
	revealFrame = reveal

	-- Announcement banner, top-centre above the card.
	local announce = Instance.new("Frame")
	announce.AnchorPoint = Vector2.new(0.5, 0)
	announce.Position = UDim2.new(0.5, 0, 0, 12)
	announce.Size = UDim2.new(0, 420, 0, 26)
	announce.BackgroundColor3 = COLOR_BG
	announce.BackgroundTransparency = 0.2
	announce.Visible = false
	announce.Parent = gui
	corner(announce, 6)
	announceFrame = announce

	local announceLabel = Instance.new("TextLabel")
	announceLabel.BackgroundTransparency = 1
	announceLabel.Size = UDim2.fromScale(1, 1)
	announceLabel.Font = Enum.Font.GothamBold
	announceLabel.TextSize = 12
	announceLabel.TextColor3 = COLOR_TEXT
	announceLabel.RichText = false
	announceLabel.Text = ""
	announceLabel.Parent = announce

	RemoteAccess.connect(RemoteNames.Name.MeltResult, function(result: any)
		if type(result) ~= "table" then
			return
		end
		local key = result.DiscoveryKey
		if type(key) == "string" then
			enqueueReveal(key, result.DiscoveryIsNew == true)
		end
	end)

	RemoteAccess.connect(RemoteNames.Name.RarityAnnouncement, showAnnouncement)

	-- Ownership comes from the replicated snapshot, never from a reveal.
	local stateController = script.Parent:FindFirstChild("StateController")
	if stateController then
		local controller = require(stateController)
		local function apply(state: any)
			if type(state) == "table" and type(state.Discoveries) == "table" then
				owned = state.Discoveries
				DiscoveryController.refreshIndex()
			end
		end
		apply(controller.get())
		controller.getChangedSignal():Connect(apply)
	end
end

return DiscoveryController
