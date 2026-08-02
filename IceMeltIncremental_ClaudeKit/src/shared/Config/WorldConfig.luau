--!strict

--[[
	WorldConfig

	Names and coordinates for the runtime object graph. Phase 00 only builds an empty
	skeleton from this; Phase 03 fills IceField and Phase 05 replaces the placeholder
	ground with real zone art. Keeping the layout here means no service ever hard-codes
	a path into Workspace.

	Zones progress along +Z. Every sign faces -Z so a player walking from the spawn
	toward +Z always reads the front face.
]]

export type ZoneLayout = {
	Center: Vector3,
	GroundSize: Vector3,
	GroundColor: Color3,
	GroundMaterial: Enum.Material,
	BoundaryHeight: number,
	SignPosition: Vector3,
}

local ZONE_LAYOUTS: { [string]: ZoneLayout } = table.freeze({
	Backyard = table.freeze({
		Center = Vector3.new(0, 0, 0),
		GroundSize = Vector3.new(220, 4, 220),
		GroundColor = Color3.fromRGB(236, 246, 252),
		GroundMaterial = Enum.Material.Snow,
		BoundaryHeight = 40,
		SignPosition = Vector3.new(-34, 9, -78),
	}),
	Cavern = table.freeze({
		Center = Vector3.new(0, 0, 400),
		GroundSize = Vector3.new(220, 4, 220),
		GroundColor = Color3.fromRGB(116, 172, 214),
		GroundMaterial = Enum.Material.Ice,
		BoundaryHeight = 40,
		SignPosition = Vector3.new(0, 9, 296),
	}),
	City = table.freeze({
		Center = Vector3.new(0, 0, 800),
		GroundSize = Vector3.new(220, 4, 220),
		GroundColor = Color3.fromRGB(158, 174, 190),
		GroundMaterial = Enum.Material.Concrete,
		BoundaryHeight = 40,
		SignPosition = Vector3.new(0, 9, 696),
	}),
})

return table.freeze({
	-- Bump when the skeleton shape changes so stale geometry is rebuilt, not patched.
	SkeletonVersion = 2,

	RootName = "IceMelt",

	ReplicatedFolders = table.freeze({
		State = "State",
	}),

	ServerFolders = table.freeze({
		Pools = "Pools",
	}),

	WorkspaceFolders = table.freeze({
		Zones = "Zones",
		Hub = "Hub",
		Effects = "Effects",
	}),

	ZoneFolders = table.freeze({
		Boundaries = "Boundaries",
		IceField = "IceField",
		Props = "Props",
		Markers = "Markers",
	}),

	-- Build order is also the intended progression order.
	ZoneOrder = table.freeze({ "Backyard", "Cavern", "City" }),

	Zones = ZONE_LAYOUTS,

	Hub = table.freeze({
		-- Backyard ground top sits at Y = 2, so a 1-stud spawn pad centres at Y = 2.5.
		SpawnPosition = Vector3.new(0, 2.5, -100),
		SpawnLookAt = Vector3.new(0, 2.5, 0),
		TitleSignPosition = Vector3.new(0, 10, -78),
		SignSize = Vector3.new(28, 10, 1),
		TitleSignSize = Vector3.new(36, 12, 1),
	}),

	BoundaryThickness = 2,
})
