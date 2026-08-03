--!strict

--[[
	IceFieldService

	Owns every ice cell: construction, durability, crack stages, destruction, and respawn.

	Three properties this is built around:

	1. No instance churn. Every cell part is created once at startup and never destroyed.
	   Melting sets it invisible and non-collidable; respawn restores it. Sustained play
	   therefore allocates nothing, which is the pooling requirement in docs/02.

	2. Lookup by arithmetic, not search. Cells sit on a regular grid, so the cells within a
	   radius are found by computing the row and column range directly. A pulse touches
	   only the handful of cells that could possibly be in range, no matter how large the
	   field is.

	3. Appearance updates only on stage change. Property writes replicate, so updating a
	   part on every point of damage would flood the network to show nothing new.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("IceMelt", 10):WaitForChild("Shared", 10)
local ConfigFolder = Shared:WaitForChild("Config", 10)

local ContentConfig = require(ConfigFolder:WaitForChild("ContentConfig", 10))
local IceFieldConfig = require(ConfigFolder:WaitForChild("IceFieldConfig", 10))
local TagNames = require(ConfigFolder:WaitForChild("TagNames", 10))
local WorldConfig = require(ConfigFolder:WaitForChild("WorldConfig", 10))

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local IceFieldService = {
	Name = "IceFieldService",
	-- After data, before the melt loop that reads cells.
	Priority = 20,
}

export type Cell = {
	Id: number,
	ZoneKey: string,
	Row: number,
	Col: number,
	Position: Vector3,
	Part: BasePart,
	MaxDurability: number,
	Durability: number,
	Alive: boolean,
	Stage: number,
	RespawnAt: number,
}

type ZoneField = {
	ZoneKey: string,
	Origin: Vector3,
	FirstId: number,
	Cells: { Cell },
}

local cellsById: { [number]: Cell } = {}
local fields: { [string]: ZoneField } = {}
local pendingRespawn: { [number]: boolean } = {}
local nextId = 1

-- === Construction ==========================================================

local function appearanceFor(zoneKey: string)
	return IceFieldConfig.Appearance[zoneKey] or IceFieldConfig.Appearance.Backyard
end

local function applyAppearance(cell: Cell)
	local look = appearanceFor(cell.ZoneKey)
	local part = cell.Part

	if not cell.Alive then
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		return
	end

	-- Blend towards the cracked colour as durability falls, so damage is readable at a
	-- glance without needing a decal per stage.
	local remaining = cell.Durability / cell.MaxDurability
	local wear = 1 - math.clamp(remaining, 0, 1)

	part.Transparency = look.Transparency + (0.35 - look.Transparency) * wear
	part.Color = look.Color:Lerp(IceFieldConfig.CrackedColor, wear * 0.8)
	part.Size = IceFieldConfig.CellSize * (1 - wear * 0.25)
	part.CanCollide = false
	part.CanQuery = true
end

local function buildZoneField(zoneKey: string, container: Instance): ZoneField?
	local layout = WorldConfig.Zones[zoneKey]
	local zone = ContentConfig.Zones[zoneKey]
	if not layout or not zone then
		warn(string.format("[IceMelt] IceFieldService: no layout or content for zone %q", zoneKey))
		return nil
	end

	local grid = IceFieldConfig.GridSize
	local spacing = IceFieldConfig.Spacing
	local half = (grid - 1) / 2

	local field: ZoneField = {
		ZoneKey = zoneKey,
		Origin = layout.Center,
		FirstId = nextId,
		Cells = {},
	}

	for row = 0, grid - 1 do
		for col = 0, grid - 1 do
			local position = Vector3.new(
				layout.Center.X + (col - half) * spacing,
				IceFieldConfig.CellBaseY,
				layout.Center.Z + (row - half) * spacing
			)

			local part = Instance.new("Part")
			part.Name = string.format("Cell_%d", nextId)
			part.Size = IceFieldConfig.CellSize
			part.CFrame = CFrame.new(position)
			part.Anchored = true
			part.CanCollide = false
			part.CastShadow = false
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.Material = appearanceFor(zoneKey).Material
			part.Parent = container

			-- Attributes let tooling and MCP inspection read a cell without a module.
			part:SetAttribute("CellId", nextId)
			part:SetAttribute("ZoneKey", zoneKey)
			CollectionService:AddTag(part, TagNames.IceCell)

			local cell: Cell = {
				Id = nextId,
				ZoneKey = zoneKey,
				Row = row,
				Col = col,
				Position = position,
				Part = part,
				MaxDurability = zone.Durability,
				Durability = zone.Durability,
				Alive = true,
				Stage = 0,
				RespawnAt = 0,
			}

			applyAppearance(cell)

			cellsById[nextId] = cell
			table.insert(field.Cells, cell)
			nextId += 1
		end
	end

	return field
end

-- === Queries ===============================================================

function IceFieldService.getCell(cellId: number): Cell?
	return cellsById[cellId]
end

--[[
	Cells within `radius` of `position` in `zoneKey`, alive only.

	Computes the row and column window from the grid pitch rather than iterating the field.
	`maxCells` is a hard stop so a huge radius cannot produce an unbounded result set.
]]
function IceFieldService.queryCells(
	zoneKey: string,
	position: Vector3,
	radius: number,
	maxCells: number
): { Cell }
	local field = fields[zoneKey]
	local result: { Cell } = {}
	if not field then
		return result
	end

	local grid = IceFieldConfig.GridSize
	local spacing = IceFieldConfig.Spacing
	local half = (grid - 1) / 2
	local origin = field.Origin

	-- Convert world position to fractional grid coordinates, then take the window that
	-- the radius could possibly reach.
	local colCentre = (position.X - origin.X) / spacing + half
	local rowCentre = (position.Z - origin.Z) / spacing + half
	local reach = radius / spacing

	local colMin = math.max(0, math.floor(colCentre - reach))
	local colMax = math.min(grid - 1, math.ceil(colCentre + reach))
	local rowMin = math.max(0, math.floor(rowCentre - reach))
	local rowMax = math.min(grid - 1, math.ceil(rowCentre + reach))

	local radiusSquared = radius * radius

	for row = rowMin, rowMax do
		for col = colMin, colMax do
			local index = row * grid + col + 1
			local cell = field.Cells[index]
			if cell and cell.Alive then
				local delta = cell.Position - position
				-- Horizontal distance only: a player standing on the slab should reach
				-- cells at their feet regardless of character height.
				local flat = delta.X * delta.X + delta.Z * delta.Z
				if flat <= radiusSquared then
					table.insert(result, cell)
					if #result >= maxCells then
						return result
					end
				end
			end
		end
	end

	return result
end

--[[
	Applies damage. Returns whether the cell was destroyed by this hit.

	Only touches the part when the crack stage actually changes, or on destruction.
]]
function IceFieldService.damageCell(cell: Cell, damage: number): boolean
	if not cell.Alive or damage <= 0 then
		return false
	end

	cell.Durability -= damage

	if cell.Durability <= 0 then
		cell.Durability = 0
		cell.Alive = false
		cell.Stage = IceFieldConfig.CrackStages

		local zone = ContentConfig.Zones[cell.ZoneKey]
		local respawnSeconds = if zone then zone.RespawnSeconds else 5
		cell.RespawnAt = os.clock() + respawnSeconds
		pendingRespawn[cell.Id] = true

		applyAppearance(cell)
		return true
	end

	local remaining = cell.Durability / cell.MaxDurability
	local stage = math.floor((1 - remaining) * IceFieldConfig.CrackStages)
	if stage ~= cell.Stage then
		cell.Stage = stage
		applyAppearance(cell)
	end

	return false
end

function IceFieldService.countAlive(zoneKey: string?): number
	local total = 0
	for _, cell in cellsById do
		if cell.Alive and (zoneKey == nil or cell.ZoneKey == zoneKey) then
			total += 1
		end
	end
	return total
end

function IceFieldService.countTotal(): number
	return nextId - 1
end

-- === Lifecycle =============================================================

local function respawnCell(cell: Cell)
	cell.Alive = true
	cell.Durability = cell.MaxDurability
	cell.Stage = 0
	cell.RespawnAt = 0
	applyAppearance(cell)
end

function IceFieldService.Start()
	local worldRoot = Workspace:FindFirstChild(WorldConfig.RootName)
	if not worldRoot then
		warn("[IceMelt] IceFieldService: world root missing; no ice fields built")
		return
	end

	local zones = worldRoot:FindFirstChild(WorldConfig.WorkspaceFolders.Zones)
	if not zones then
		warn("[IceMelt] IceFieldService: Zones folder missing; no ice fields built")
		return
	end

	for _, zoneKey in ContentConfig.ZoneOrder do
		local zoneFolder = zones:FindFirstChild(zoneKey)
		local container = zoneFolder and zoneFolder:FindFirstChild(WorldConfig.ZoneFolders.IceField)
		if not container then
			warn(
				string.format("[IceMelt] IceFieldService: no IceField folder for zone %q", zoneKey)
			)
			continue
		end

		-- Idempotent across a rebuild: clear anything already there before repopulating.
		for _, child in container:GetChildren() do
			child:Destroy()
		end

		local field = buildZoneField(zoneKey, container)
		if field then
			fields[zoneKey] = field
		end
	end

	--[[
		One sweep for every pending respawn, rather than a timer per cell. With 768 cells a
		per-cell task.delay would mean hundreds of scheduler entries doing work that
		batches trivially.
	]]
	task.spawn(function()
		while true do
			task.wait(IceFieldConfig.RespawnSweepSeconds)

			local now = os.clock()
			for cellId in pendingRespawn do
				local cell = cellsById[cellId]
				if not cell then
					pendingRespawn[cellId] = nil
				elseif now >= cell.RespawnAt then
					respawnCell(cell)
					pendingRespawn[cellId] = nil
				end
			end
		end
	end)
end

return IceFieldService
