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
	--[[
		16 x 16 = 256 cells per zone, 768 total, on a 6 stud pitch giving a 96 x 96 field
		inside the 220 x 220 zone slab.

		Pitch sets the early pacing, so it is tuned rather than picked.

		Power is 10 damage per second (docs/03) and a Backyard cell has 10 durability, so a
		cell breaks after one full second inside the melt radius. What matters is therefore
		how many cells the base 4.5 stud radius holds at once, which is set by the pitch.

		Measured with realistic play - walk to the ice, then short hops with a pause in each
		spot - against the 15 to 30 second first-upgrade target in docs/01:
		    8 stud pitch -> 0.34 Heat/sec, first upgrade ~43s (too slow)
		    6 stud pitch -> see PROJECT_STATUS Phase 04 evidence

		Pitch is the right lever because it is a choice made in this file. Power's cost of
		15 and Backyard's durability of 10 come from docs/03 and should not be bent to fix a
		pacing problem this file created.

		Note for later tuning: damage accrues only while a cell is inside the radius, so a
		player sprinting across the field melts far less than one standing in it. That is
		intended - the ice melts around you - but any pacing measurement has to model
		realistic movement rather than a continuous sprint, or it will read far too low.
	]]
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
		Client effect pool. Parts are created once and reused round-robin, so instance count
		never rises with reward size.

		The pool alone is not the whole story, and the earlier comment here was wrong: reusing
		a part does not stop the emitter being triggered, so a 120-cell chain still issued 120
		Emit calls against these 48 parts. MeltEffectsController now budgets bursts per batch
		and spreads them across the blast, which is what actually bounds particle count.
	]]
	EffectPoolSize = 48,

	-- One aggregated sound per batch, never one per cell. See docs/07.
	MaxSoundsPerSecond = 12,
})
