--!strict

--[[
	WorldSkeleton

	Builds the Phase 00 placeholder world from WorldConfig and ContentConfig: a spawn,
	hub signage, one ground slab per zone, invisible safe boundaries so nobody can fall
	out of the map, and the folders/tags every later phase attaches to.

	Deliberately code-driven rather than hand-placed in Studio, so the world is
	reproducible from source control and cannot silently drift from configuration.

	Idempotent. Re-running reuses matching instances. When WorldConfig.SkeletonVersion
	changes the previous skeleton is cleared and rebuilt rather than patched, which
	avoids stale geometry from an older layout surviving forever.

	Phase 03 fills each zone's IceField folder. Phase 05 replaces the ground slabs with
	real zone art and adds travel pads.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("IceMelt"):WaitForChild("Shared")
local ConfigFolder = Shared:WaitForChild("Config")

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig"))
local GameConfig = require(ConfigFolder:WaitForChild("GameConfig"))
local TagNames = require(ConfigFolder:WaitForChild("TagNames"))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig"))
local ZoneStyleConfig = require(ConfigFolder:WaitForChild("ZoneStyleConfig"))

export type BuildResult = {
	ZonesBuilt: number,
	Rebuilt: boolean,
	ForeignSpawnsDisabled: number,
}

local WorldSkeleton = {}

local SIGN_FACE_COLOR = Color3.fromRGB(24, 34, 48)
local SIGN_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SIGN_ACCENT_COLOR = Color3.fromRGB(255, 176, 92)

local function ensureChild(parent: Instance, name: string, className: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		if existing.ClassName == className then
			return existing
		end
		existing:Destroy()
	end

	local created = Instance.new(className :: any) :: Instance
	created.Name = name
	created.Parent = parent
	return created
end

local function ensureFolder(parent: Instance, name: string): Folder
	return ensureChild(parent, name, "Folder") :: Folder
end

local function ensureTag(instance: Instance, tag: string)
	if not CollectionService:HasTag(instance, tag) then
		CollectionService:AddTag(instance, tag)
	end
end

local function withCommas(value: number): string
	local text = string.format("%d", value)
	local formatted = text
	while true do
		local replaced: string, count: number = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end
	return formatted
end

--[[
	A flat, unlit, double-sided-enough placeholder sign. Two labels so the headline and
	the supporting line can scale independently.
]]
local function buildSign(
	parent: Instance,
	name: string,
	size: Vector3,
	position: Vector3,
	heading: string,
	subtitle: string
): Part
	local sign = ensureChild(parent, name, "Part") :: Part
	sign.Size = size
	sign.CFrame = CFrame.new(position)
	sign.Anchored = true
	sign.CanCollide = false
	sign.CanQuery = false
	sign.CanTouch = false
	sign.CastShadow = false
	sign.Color = SIGN_FACE_COLOR
	sign.Material = Enum.Material.SmoothPlastic
	sign.TopSurface = Enum.SurfaceType.Smooth
	sign.BottomSurface = Enum.SurfaceType.Smooth

	local gui = ensureChild(sign, "Display", "SurfaceGui") :: SurfaceGui
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.AlwaysOnTop = false

	local headingLabel = ensureChild(gui, "Heading", "TextLabel") :: TextLabel
	headingLabel.BackgroundTransparency = 1
	headingLabel.Size = UDim2.fromScale(1, 0.55)
	headingLabel.Position = UDim2.fromScale(0, 0.06)
	headingLabel.Font = Enum.Font.GothamBold
	headingLabel.TextScaled = true
	headingLabel.TextColor3 = SIGN_TEXT_COLOR
	headingLabel.Text = heading

	local subtitleLabel = ensureChild(gui, "Subtitle", "TextLabel") :: TextLabel
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Size = UDim2.fromScale(1, 0.3)
	subtitleLabel.Position = UDim2.fromScale(0, 0.63)
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextScaled = true
	subtitleLabel.TextColor3 = SIGN_ACCENT_COLOR
	subtitleLabel.Text = subtitle

	ensureTag(sign, TagNames.Sign)
	return sign
end

local function buildBoundaries(
	zoneFolder: Instance,
	center: Vector3,
	groundSize: Vector3,
	height: number
)
	local boundaries = ensureFolder(zoneFolder, WorldConfig.ZoneFolders.Boundaries)

	local thickness = WorldConfig.BoundaryThickness
	local groundTopY = center.Y + groundSize.Y / 2
	local wallY = groundTopY + height / 2

	local halfX = groundSize.X / 2 + thickness / 2
	local halfZ = groundSize.Z / 2 + thickness / 2

	local walls = {
		{
			Name = "North",
			Size = Vector3.new(groundSize.X + thickness * 2, height, thickness),
			Position = Vector3.new(center.X, wallY, center.Z + halfZ),
		},
		{
			Name = "South",
			Size = Vector3.new(groundSize.X + thickness * 2, height, thickness),
			Position = Vector3.new(center.X, wallY, center.Z - halfZ),
		},
		{
			Name = "East",
			Size = Vector3.new(thickness, height, groundSize.Z + thickness * 2),
			Position = Vector3.new(center.X + halfX, wallY, center.Z),
		},
		{
			Name = "West",
			Size = Vector3.new(thickness, height, groundSize.Z + thickness * 2),
			Position = Vector3.new(center.X - halfX, wallY, center.Z),
		},
	}

	for _, spec in walls do
		local wall = ensureChild(boundaries, spec.Name, "Part") :: Part
		wall.Size = spec.Size
		wall.CFrame = CFrame.new(spec.Position)
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Transparency = 1
		wall.Material = Enum.Material.SmoothPlastic
		ensureTag(wall, TagNames.Boundary)
	end
end

--[[
	Decorative props around a zone's perimeter, from ZoneStyleConfig.

	Placement uses a seeded generator so every server and every rebuild produces the same
	world. An unseeded math.random would make two servers visually different, and would make
	a bug report impossible to reproduce.

	Props are pushed to a ring outside the ice field so the playable middle stays clear, and
	carry no collision or queries: they exist to make the zones distinguishable, not to be
	something the melt loop has to reason about.
]]
local function buildZoneProps(zoneFolder: Instance, zoneKey: string, layout: any)
	local style = ZoneStyleConfig.Styles[zoneKey] or ZoneStyleConfig.Fallback
	local propsFolder = ensureFolder(zoneFolder, WorldConfig.ZoneFolders.Props)

	for _, child in propsFolder:GetChildren() do
		child:Destroy()
	end

	-- Seeded per zone so zones do not share a layout.
	local rng = Random.new(ZoneStyleConfig.PlacementSeed + #zoneKey * 7919)
	local halfExtent = layout.GroundSize.X / 2
	local groundTop = layout.Center.Y + layout.GroundSize.Y / 2

	for _, spec in style.Props do
		for index = 1, spec.Count do
			local angle = rng:NextNumber(0, math.pi * 2)
			local distance = halfExtent * rng:NextNumber(spec.MinRadius, spec.MaxRadius)
			local jitter = if spec.HeightJitter > 0 then rng:NextNumber(0, spec.HeightJitter) else 0
			local height = spec.Size.Y + jitter

			local part = Instance.new("Part")
			part.Name = string.format("%s_%d", spec.Kind, index)
			part.Size = Vector3.new(spec.Size.X, height, spec.Size.Z)
			part.CFrame = CFrame.new(
				layout.Center.X + math.cos(angle) * distance,
				groundTop + height / 2,
				layout.Center.Z + math.sin(angle) * distance
			) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Color = spec.Color
			part.Material = spec.Material
			part.Parent = propsFolder
		end
	end
end

--[[
	The pad a player lands on when travelling here. Tagged so ZoneService and later phases
	can find it without a hard-coded path.
]]
local function buildTravelPad(zoneFolder: Instance, zoneKey: string, layout: any)
	local markers = ensureFolder(zoneFolder, WorldConfig.ZoneFolders.Markers)

	local pad = ensureChild(markers, "TravelPad", "Part") :: Part
	pad.Size = Vector3.new(14, 0.6, 14)
	pad.CFrame = CFrame.new(layout.ArrivalPosition - Vector3.new(0, 2.2, 0))
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 176, 92)
	pad.Transparency = 0.35
	pad:SetAttribute("ZoneKey", zoneKey)
	ensureTag(pad, TagNames.TravelPad)
end

local function buildZone(zonesFolder: Instance, zoneKey: string, zoneIndex: number): boolean
	local layout = WorldConfig.Zones[zoneKey]
	local content = ContentConfig.Zones[zoneKey]

	if not layout then
		warn(
			string.format(
				"[IceMelt] WorldSkeleton: no WorldConfig.Zones entry for %q. Skipping.",
				zoneKey
			)
		)
		return false
	end
	if not content then
		warn(
			string.format(
				"[IceMelt] WorldSkeleton: no ContentConfig.Zones entry for %q. Skipping.",
				zoneKey
			)
		)
		return false
	end

	local zoneFolder = ensureFolder(zonesFolder, zoneKey)
	ensureTag(zoneFolder, TagNames.Zone)

	-- Attributes mirror configuration so tools, plugins, and MCP inspection can read the
	-- zone's intent without requiring a module.
	zoneFolder:SetAttribute("ZoneKey", zoneKey)
	zoneFolder:SetAttribute("ZoneIndex", zoneIndex)
	zoneFolder:SetAttribute("DisplayName", content.DisplayName)
	zoneFolder:SetAttribute("UnlockCost", content.Cost)
	zoneFolder:SetAttribute("BaseDurability", content.Durability)
	zoneFolder:SetAttribute("BaseHeat", content.Heat)
	zoneFolder:SetAttribute("RespawnSeconds", content.RespawnSeconds)
	zoneFolder:SetAttribute("LuckMultiplier", content.Luck)

	local ground = ensureChild(zoneFolder, "Ground", "Part") :: Part
	ground.Size = layout.GroundSize
	ground.CFrame = CFrame.new(layout.Center)
	ground.Anchored = true
	ground.CanCollide = true
	ground.Color = layout.GroundColor
	ground.Material = layout.GroundMaterial
	ground.TopSurface = Enum.SurfaceType.Smooth
	ground.BottomSurface = Enum.SurfaceType.Smooth
	ensureTag(ground, TagNames.ZoneGround)

	buildBoundaries(zoneFolder, layout.Center, layout.GroundSize, layout.BoundaryHeight)

	-- Empty containers claimed now so later phases never have to create paths ad hoc.
	local iceField = ensureFolder(zoneFolder, WorldConfig.ZoneFolders.IceField)
	ensureTag(iceField, TagNames.IceField)
	iceField:SetAttribute("ZoneKey", zoneKey)

	buildZoneProps(zoneFolder, zoneKey, layout)
	buildTravelPad(zoneFolder, zoneKey, layout)

	local markers = ensureFolder(zoneFolder, WorldConfig.ZoneFolders.Markers)

	local subtitle = if content.Cost > 0
		then string.format("Unlock: %s Heat", withCommas(content.Cost))
		else "Starting zone"

	buildSign(
		markers,
		"ZoneSign",
		WorldConfig.Hub.SignSize,
		layout.SignPosition,
		content.DisplayName,
		subtitle
	)

	return true
end

--[[
	The Baseplate template ships with a SpawnLocation at the origin, which sits inside the
	Backyard ground slab. Any spawn outside the hub is disabled rather than destroyed, so
	the change is obvious and reversible in Studio.
]]
local function disableForeignSpawns(hubSpawn: SpawnLocation): number
	local disabled = 0
	for _, descendant in Workspace:GetDescendants() do
		if descendant ~= hubSpawn and descendant:IsA("SpawnLocation") and descendant.Enabled then
			descendant.Enabled = false
			disabled += 1
			warn(
				string.format(
					"[IceMelt] WorldSkeleton: disabled foreign SpawnLocation at %s. "
						.. "The hub spawn is the only supported spawn point.",
					descendant:GetFullName()
				)
			)
		end
	end
	return disabled
end

local function buildHub(worldRoot: Instance): SpawnLocation
	local hub = ensureFolder(worldRoot, WorldConfig.WorkspaceFolders.Hub)

	local spawn = ensureChild(hub, "Spawn", "SpawnLocation") :: SpawnLocation
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.lookAt(WorldConfig.Hub.SpawnPosition, WorldConfig.Hub.SpawnLookAt)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.Color = Color3.fromRGB(255, 176, 92)
	spawn.Material = Enum.Material.Neon
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	ensureTag(spawn, TagNames.Spawn)

	local signage = ensureFolder(hub, "Signage")
	buildSign(
		signage,
		"TitleSign",
		WorldConfig.Hub.TitleSignSize,
		WorldConfig.Hub.TitleSignPosition,
		GameConfig.GameName,
		"Walk into the ice to melt it."
	)

	return spawn
end

--[[
	Builds or reconciles the whole skeleton. Returns counts so the caller can log a single
	line of evidence instead of a stream of prints.
]]
function WorldSkeleton.build(worldRoot: Folder): BuildResult
	local existingVersion = worldRoot:GetAttribute("SkeletonVersion")
	local rebuilt = false

	if existingVersion ~= nil and existingVersion ~= WorldConfig.SkeletonVersion then
		for _, child in worldRoot:GetChildren() do
			child:Destroy()
		end
		rebuilt = true
	end

	local zonesFolder = ensureFolder(worldRoot, WorldConfig.WorkspaceFolders.Zones)
	ensureFolder(worldRoot, WorldConfig.WorkspaceFolders.Effects)

	local zonesBuilt = 0
	for index, zoneKey in WorldConfig.ZoneOrder do
		if buildZone(zonesFolder, zoneKey, index) then
			zonesBuilt += 1
		end
	end

	local hubSpawn = buildHub(worldRoot)
	local foreignSpawnsDisabled = disableForeignSpawns(hubSpawn)

	worldRoot:SetAttribute("SkeletonVersion", WorldConfig.SkeletonVersion)
	worldRoot:SetAttribute("Environment", GameConfig.Environment)
	worldRoot:SetAttribute("ZoneCount", zonesBuilt)

	return {
		ZonesBuilt = zonesBuilt,
		Rebuilt = rebuilt,
		ForeignSpawnsDisabled = foreignSpawnsDisabled,
	}
end

return WorldSkeleton
