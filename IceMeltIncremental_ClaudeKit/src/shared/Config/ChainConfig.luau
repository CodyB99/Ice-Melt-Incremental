--!strict

--[[
	ChainConfig

	Tuning for how chain reactions arm and fire.

	Deliberately separate from `ContentConfig.Chains`. That table holds the three documented
	chain shapes from docs/04 — radius, cell cap, whether it announces — and none of those
	values are changed by this file. What lives here is everything docs/ does not specify: how
	often a seed arms, how many can stand at once, and how long a burnt seed stays cold.

	Every number here is a local engineering choice, in the same class as the ice field pitch,
	and none of them is a security limit. The security limits are in `GameConfig.Limits`,
	because a cap that lives in the file a designer edits to tune content is not a cap.
]]

return table.freeze({
	--[[
		Chance that a cell arms as a chain seed when the field sweeps for candidates.

		Read against the standing caps below rather than in isolation: arming is what refills a
		zone toward its cap, so a low chance with a small cap produces a steady trickle rather
		than a burst after every clear.

		Ordered commonest first. The Unstable Reactor is deliberately an order of magnitude
		rarer than the others, matching "rare city chain" in docs/04.
	]]
	ArmChancePerSweep = table.freeze({
		HeatPocket = 0.020,
		LavaCapsule = 0.006,
		UnstableReactor = 0.0006,
	}),

	--[[
		How many armed seeds may stand in one zone at once, per chain type.

		This is what actually bounds chain frequency. Without it, arming chance alone would
		make chain rate scale with how fast the player clears the field, so a stronger player
		would see proportionally more chains for free.
	]]
	MaxArmedPerZone = table.freeze({
		HeatPocket = 6,
		LavaCapsule = 2,
		UnstableReactor = 1,
	}),

	-- How often the server looks for cells to arm. One sweep for every zone.
	ArmSweepSeconds = 2,

	--[[
		A cell that has just been a seed cannot re-arm for this long.

		Stops a player parking on one spot and farming the same cell as it respawns, which is
		the cheapest possible chain exploit and needs no modified client at all.
	]]
	SeedCooldownSeconds = 25,

	-- Minimum spacing between armed seeds of the same chain, in studs. Keeps two Lava Capsules
	-- from arming on top of each other and firing as one indistinguishable blast.
	MinSeedSpacingStuds = 18,

	--[[
		A chain must destroy at least this many cells before it is worth telling the whole
		server about. An Unstable Reactor that catches three cells at the edge of a cleared
		field is not the spectacle the announcement promises.
	]]
	MinCellsToAnnounce = 8,
})
