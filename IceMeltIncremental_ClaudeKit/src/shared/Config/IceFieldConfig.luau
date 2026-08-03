--!strict

--[[
	IceFieldConfig

	Shape of the ice grid in each zone.

	The grid is regular on purpose: a fixed row/column pitch means a melt pulse can compute
	exactly which cells fall inside its radius with index arithmetic, instead of scanning
	every cell in the zone. That is what keeps the melt loop cheap with several players
	pulsing many times a second.

	Cell parts are created once at startup and never destroyed. Melting hides a cell and
	respawn restores it, so sustained play produces no instance churn at all.
]]

return table.freeze({
	-- 16 x 16 = 256 cells per zone, 768 total. Spacing 6 studs gives a 96 x 96 stud field,
	-- comfortably inside the 220 x 220 zone slab built by WorldSkeleton.
	GridSize = 16,
	Spacing = 6,

	CellSize = Vector3.new(4.6, 4.6, 4.6),

	-- Sits on the zone slab, whose top surface is Y = 2.
	CellBaseY = 4.4,

	--[[
		Crack stages. A cell's appearance changes only when it crosses a stage boundary,
		not on every point of damage: property changes replicate, so updating on every hit
		would flood the network for no visible gain.
	]]
	CrackStages = 4,

	-- Visual treatment per zone, keyed by zone. Colour shifts warmer as a cell weakens.
	Appearance = table.freeze({
		Backyard = table.freeze({
			Color = Color3.fromRGB(196, 232, 250),
			Material = Enum.Material.Ice,
			Transparency = 0.25,
		}),
		Cavern = table.freeze({
			Color = Color3.fromRGB(120, 190, 235),
			Material = Enum.Material.Ice,
			Transparency = 0.2,
		}),
		City = table.freeze({
			Color = Color3.fromRGB(170, 200, 220),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
		}),
	}),

	-- Colour a cell tends towards as it approaches destruction.
	CrackedColor = Color3.fromRGB(255, 214, 170),

	--[[
		How often the server sweeps for cells due to respawn. One sweep for the whole game
		rather than a timer per cell: 768 pending timers would be 768 scheduler entries for
		work that is trivially batched.
	]]
	RespawnSweepSeconds = 0.5,

	--[[
		Client effect pool. Bursts beyond this in a single batch are dropped rather than
		allocating, because a chain reaction must not be able to spike instance count.
	]]
	EffectPoolSize = 48,

	-- One aggregated sound per batch, never one per cell. See docs/07.
	MaxSoundsPerSecond = 12,
})
