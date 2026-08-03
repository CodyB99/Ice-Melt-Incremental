--!strict

--[[
	ZoneStyleConfig

	Per-zone props, lighting, and ambience, from the art direction in docs/04 and docs/07.

	Everything is procedural from primitives. docs/07 says to use primitives until approved
	art exists, and generating from a table means Phase 08 can replace a zone's look by
	editing this file rather than rebuilding geometry.

	Props are decorative only: no collision, no queries, no scripts. They exist to make the
	three zones instantly distinguishable, which is the acceptance criterion, without adding
	anything the melt loop has to reason about.

	Lighting is applied client-side by ZoneController as the player travels, so each player
	sees the zone they are actually in. Setting it on the server would give everyone the
	lighting of whichever zone someone entered last.
]]

export type PropSpec = {
	Kind: string,
	Count: number,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	-- Placement ring, as a fraction of the zone half-extent.
	MinRadius: number,
	MaxRadius: number,
	HeightJitter: number,
}

export type ZoneStyle = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogEnd: number,
	Brightness: number,
	Props: { PropSpec },
}

local function prop(
	kind: string,
	count: number,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	minRadius: number,
	maxRadius: number,
	heightJitter: number
): PropSpec
	return table.freeze({
		Kind = kind,
		Count = count,
		Size = size,
		Color = color,
		Material = material,
		MinRadius = minRadius,
		MaxRadius = maxRadius,
		HeightJitter = heightJitter,
	})
end

local STYLES: { [string]: ZoneStyle } = table.freeze({
	--[[
		Frozen Backyard: bright, friendly, onboarding. Fence posts and garden clutter around
		the edges so the middle stays clear for the first melt.
	]]
	Backyard = table.freeze({
		Ambient = Color3.fromRGB(140, 150, 165),
		OutdoorAmbient = Color3.fromRGB(160, 175, 195),
		FogColor = Color3.fromRGB(226, 240, 252),
		FogEnd = 900,
		Brightness = 2.5,
		Props = table.freeze({
			prop(
				"FencePost",
				28,
				Vector3.new(1, 8, 1),
				Color3.fromRGB(150, 112, 78),
				Enum.Material.Wood,
				0.86,
				0.98,
				0
			),
			prop(
				"Shed",
				2,
				Vector3.new(14, 12, 12),
				Color3.fromRGB(122, 84, 62),
				Enum.Material.WoodPlanks,
				0.62,
				0.78,
				0
			),
			prop(
				"Toy",
				16,
				Vector3.new(2.5, 2.5, 2.5),
				Color3.fromRGB(232, 96, 96),
				Enum.Material.SmoothPlastic,
				0.55,
				0.8,
				0
			),
		}),
	}),

	--[[
		Ice Cavern: dark blue crystal cave. Tall spikes and a low fog ceiling so it reads as
		enclosed even though it is an open slab.
	]]
	Cavern = table.freeze({
		Ambient = Color3.fromRGB(48, 62, 92),
		OutdoorAmbient = Color3.fromRGB(58, 78, 112),
		FogColor = Color3.fromRGB(30, 54, 92),
		FogEnd = 320,
		Brightness = 1.2,
		Props = table.freeze({
			prop(
				"CrystalSpike",
				34,
				Vector3.new(4, 22, 4),
				Color3.fromRGB(96, 176, 240),
				Enum.Material.Glass,
				0.6,
				0.99,
				6
			),
			prop(
				"Stalagmite",
				22,
				Vector3.new(6, 14, 6),
				Color3.fromRGB(70, 96, 130),
				Enum.Material.Slate,
				0.5,
				0.95,
				2
			),
			prop(
				"GlowShard",
				14,
				Vector3.new(2, 5, 2),
				Color3.fromRGB(120, 220, 255),
				Enum.Material.Neon,
				0.45,
				0.9,
				3
			),
		}),
	}),

	--[[
		Frozen City: a skyline of frozen towers around the edge. docs/04 says the skyline
		should sell progress without needing enterable buildings, so these are tall blocks
		pushed to the perimeter.
	]]
	City = table.freeze({
		Ambient = Color3.fromRGB(96, 106, 124),
		OutdoorAmbient = Color3.fromRGB(118, 132, 156),
		FogColor = Color3.fromRGB(150, 168, 190),
		FogEnd = 700,
		Brightness = 1.8,
		Props = table.freeze({
			prop(
				"Tower",
				26,
				Vector3.new(16, 70, 16),
				Color3.fromRGB(128, 148, 172),
				Enum.Material.Concrete,
				0.98,
				1.35,
				28
			),
			prop(
				"LampPost",
				20,
				Vector3.new(1, 14, 1),
				Color3.fromRGB(64, 70, 82),
				Enum.Material.Metal,
				0.6,
				0.92,
				0
			),
			prop(
				"Car",
				14,
				Vector3.new(6, 4, 12),
				Color3.fromRGB(150, 60, 60),
				Enum.Material.Metal,
				0.5,
				0.88,
				0
			),
		}),
	}),
})

return table.freeze({
	Styles = STYLES,
	Fallback = STYLES.Backyard,
	-- Seeded so prop placement is identical on every server and every rebuild.
	PlacementSeed = 20260802,
})
