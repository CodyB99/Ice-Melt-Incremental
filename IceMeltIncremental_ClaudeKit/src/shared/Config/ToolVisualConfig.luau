--!strict

--[[
	ToolVisualConfig

	Placeholder appearance for the eight heat tools, built from primitives rather than
	meshes.

	docs/04 requires each tool to have a distinct silhouette so progression is readable at a
	glance, and docs/07 says to use primitives until approved art exists. Driving that from
	configuration means Phase 08 can swap in real models by changing this table, without
	touching ToolService.

	Silhouettes get physically larger and warmer through the progression, so an upgrade is
	obvious without reading a number.
]]

export type ToolVisual = {
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	-- Emitted particle colour for the tool's idle glow.
	GlowColor: Color3,
	GlowRate: number,
	-- Offset from the right hand, in the hand's local space.
	Offset: CFrame,
}

local function visual(
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	glow: Color3,
	glowRate: number
): ToolVisual
	return table.freeze({
		Size = size,
		Color = color,
		Material = material,
		GlowColor = glow,
		GlowRate = glowRate,
		Offset = CFrame.new(0, -1.2, 0),
	})
end

local VISUALS: { [string]: ToolVisual } = table.freeze({
	Match = visual(
		Vector3.new(0.12, 1.1, 0.12),
		Color3.fromRGB(222, 196, 160),
		Enum.Material.Wood,
		Color3.fromRGB(255, 190, 110),
		4
	),
	Candle = visual(
		Vector3.new(0.32, 1.5, 0.32),
		Color3.fromRGB(245, 240, 220),
		Enum.Material.SmoothPlastic,
		Color3.fromRGB(255, 200, 120),
		8
	),
	Torch = visual(
		Vector3.new(0.42, 2.0, 0.42),
		Color3.fromRGB(120, 84, 52),
		Enum.Material.Wood,
		Color3.fromRGB(255, 160, 70),
		16
	),
	Blowtorch = visual(
		Vector3.new(0.6, 1.9, 0.6),
		Color3.fromRGB(70, 130, 190),
		Enum.Material.Metal,
		Color3.fromRGB(120, 200, 255),
		26
	),
	Flamethrower = visual(
		Vector3.new(0.8, 2.4, 1.4),
		Color3.fromRGB(60, 62, 68),
		Enum.Material.Metal,
		Color3.fromRGB(255, 130, 50),
		40
	),
	HeatCannon = visual(
		Vector3.new(1.1, 1.1, 3.0),
		Color3.fromRGB(90, 96, 110),
		Enum.Material.Metal,
		Color3.fromRGB(255, 96, 40),
		60
	),
	LavaCore = visual(
		Vector3.new(1.5, 1.5, 1.5),
		Color3.fromRGB(255, 90, 30),
		Enum.Material.Neon,
		Color3.fromRGB(255, 140, 40),
		90
	),
	MiniSun = visual(
		Vector3.new(2.2, 2.2, 2.2),
		Color3.fromRGB(255, 226, 120),
		Enum.Material.Neon,
		Color3.fromRGB(255, 240, 160),
		140
	),
})

return table.freeze({
	Visuals = VISUALS,
	Fallback = VISUALS.Match,
})
